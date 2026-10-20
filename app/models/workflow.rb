class Workflow < ApplicationRecord
  belongs_to :project
  has_many :stages, -> { order(:position, :id) }, dependent: :destroy

  enum :status, { pending: 0, implementing: 1, reviewing: 2, done: 3, errored: 4, merged: 5, jira_updated: 6, waiting: 7,
                 uat_waiting: 8, uat_testing: 9, uat_tested: 10, local_testing: 11 }

  # development: a Jira ticket / personal task we implement ourselves.
  # pr_review: someone else's PR (found in a Slack mention) that we review.
  # runbook: a deploy/release-style run with its own ordered stages (any project can have many),
  # paused for a person (Next) after each.
  enum :kind, { development: 0, pr_review: 1, runbook: 2 }

  # Accepts a Slack thread id (`1760000000.123456`) or a message link (`.../archives/C123/p1760000000123456`).
  def slack_review_thread_ts=(value)
    text = value.to_s.strip
    super(text[%r{/p(\d{10})(\d{6})}] ? "#{$1}.#{$2}" : text.presence)
  end

  # Development workflows not started yet. Brainstorming only adds more once none are left; every other status is
  # irrelevant to it (implementing ones are shown to the agent so it doesn't repeat them, done ones are in the code).
  QUEUED_STATUSES = %w[pending].freeze
  SUMMARY_LENGTH = 100
  # Columns cleared when an agent run finishes or fails; merge into the workflow's next update!.
  AI_RUN_RESET = { processing: false, ai_pid: nil, ai_log_path: nil, ai_started_at: nil, ai_log_offset: 0 }.freeze

  scope :queued, -> { development.where(status: QUEUED_STATUSES) }

  # Status -> stage type maps live in Workflows::StageResolver; aliased here for existing callers.
  STAGE_TYPE_BY_STATUS = Workflows::StageResolver::STAGE_TYPE_BY_STATUS
  SIMPLE_STAGE_TYPE_BY_STATUS = Workflows::StageResolver::SIMPLE_STAGE_TYPE_BY_STATUS
  PR_REVIEW_STAGE_TYPE_BY_STATUS = Workflows::StageResolver::PR_REVIEW_STAGE_TYPE_BY_STATUS

  validates :jira_ticket, presence: true, if: :jira_development?
  validates :branch_name, presence: true, if: :jira_development?
  validates :github_reviewer, presence: true, if: :jira_development?
  validates :task_description, presence: true, if: :personal_development?
  validates :github_pr_url, presence: true, if: :pr_review?
  validate :pr_review_needs_github_project, if: :pr_review?
  validates :github_pr_url, format: { with: %r{\Ahttps://github\.com/[^/\s]+/[^/\s]+/pull/\d+\z}, message: "must be a github.com pull request URL" }, allow_blank: true

  validate :variable_names_are_placeholders
  validate :copy_source_is_a_runbook_of_this_project, if: :runbook?

  # Create-time only: id of another runbook workflow of the project whose stages this one starts with.
  attr_accessor :copy_stages_from_id

  after_create :seed_stages
  after_destroy :purge_images

  # Reference images are plain files on disk; see Workflows::ImageStore.
  def image_store
    Workflows::ImageStore.new(workflow_id: id)
  end

  def image_dir
    image_store.dir
  end

  def image_paths
    image_store.paths
  end

  # `uploads` are ActionDispatch::Http::UploadedFile objects. Returns the number saved.
  def add_images(uploads)
    image_store.add(uploads)
  end

  def remove_image(name)
    image_store.remove(name)
  end

  # Position for a stage appended after this workflow's existing ones.
  def next_stage_position
    (stages.maximum(:position) || 0) + 1
  end

  # comma-separated skill names entered in the UI, rendered into the {SKILLS} placeholder
  def skill_list
    skills.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  # The in-flight status an errored workflow goes back to: reviewing once a PR
  # exists (personal-project and PR-review workflows never reach it), otherwise implementing.
  def resume_status
    return :uat_testing if uat_test_at.present?
    return :local_testing if local_test_unfinished?

    development? && github_pr_url.present? ? :reviewing : :implementing
  end

  # One short line for compact listings (the brainstorm agent's backlog), however the workflow was made.
  def brief
    (summary.presence || label).to_s.squish.truncate(SUMMARY_LENGTH)
  end

  # "org/repo#123" for PR-review workflows, otherwise the Jira ticket / task.
  def label
    if runbook?
      summary = variables.values.compact_blank.join(" · ").squish.truncate(60)
      summary.presence || "Run ##{id}"
    elsif pr_review?
      github_pr_url.to_s[%r{github\.com/([^/]+/[^/]+)/pull/(\d+)}] && "#{$1}##{$2}"
    elsif project.personal?
      task_description.to_s
    else
      jira_ticket.to_s
    end
  end

  def variables
    super || {}
  end

  # Names a stage produced at run time (`VAR: NAME=value` in its output), as opposed to inputs the user typed.
  def output_variable_names
    StageRun.where(stage_id: stages.select(:id), action: "stage_completed").pluck(:output)
            .flat_map { |output| AiCli::Output.new(output).variables.keys }.uniq
  end

  # The variables the user set up front (channel, CSS group …), without anything a stage emitted.
  def input_variables
    variables.except(*output_variable_names)
  end

  # Edited in the UI as one `NAME=value` per line.
  def variables_text
    variables.map { |name, value| "#{name}=#{value.to_s.gsub("\n", "\\n")}" }.join("\n")
  end

  def variables_text=(text)
    self.variables = text.to_s.lines.filter_map do |line|
      name, value = line.strip.split("=", 2)
      [ name.strip.upcase, value.to_s.strip.gsub("\\n", "\n") ] if name.present?
    end.to_h
  end

  # Pending -> implementing (a runbook starts at its first stage). False when it was already started.
  def start!
    return false unless pending?

    runbook? ? start_runbook! : update!(status: :implementing)
    true
  end

  # The runbook's "Run stage" button is only valid on an implementing runbook that isn't mid-run.
  def can_run_stage?
    runbook? && implementing? && !processing?
  end

  # Flags the runbook so the scheduler runs its current stage and carries on. False when no stage is ready.
  # The caller enqueues WorkflowSchedulerJob.
  def request_stage_run!
    return false unless can_run_stage?

    update!(auto_run: true)
    true
  end

  # The runbook's Next button is only valid while a finished stage is waiting for it.
  def can_advance?
    runbook? && awaiting_next?
  end

  # Errored -> the in-flight status chosen by resume_status, logging a 'resumed' StageRun. False unless errored.
  def resume!
    return false unless errored?

    transaction do
      update!(status: resume_status)
      current_stage&.stage_runs&.create!(action: "resumed")
    end
    true
  end

  def can_rollback_to_review?
    done? && development? && github_pr_url.present?
  end

  # Done development workflow with a PR -> reviewing, logging a 'rolled_back_to_review' StageRun.
  def rollback_to_review!
    return false unless can_rollback_to_review?

    transaction do
      update!(status: :reviewing)
      current_stage&.stage_runs&.create!(action: "rolled_back_to_review")
    end
    true
  end

  # The runbook state machine lives in Workflows::RunbookNavigator.
  def start_runbook! = Workflows::RunbookNavigator.new(self).start!

  def advance! = Workflows::RunbookNavigator.new(self).advance!

  def next_runbook_stage = Workflows::RunbookNavigator.new(self).next_stage

  def previous_runbook_stage = Workflows::RunbookNavigator.new(self).previous_stage

  def current_stage
    return stages.find_by(id: current_stage_id) if runbook?

    stage_type = Workflows::StageResolver.stage_type_for(status: status, kind: kind, personal: project.personal?)
    return nil unless stage_type

    # The Jira-update and UAT-test stages aren't seeded with the workflow (older workflows
    # predate it), so create it the first time it's needed.
    return stages.find_or_create_by!(stage_type: stage_type) if Workflows::StageResolver::LAZY_STAGE_TYPES.include?(stage_type)

    stages.find_by(stage_type: stage_type)
  end

  # Jira-project development workflows that got a PR: the ones whose ticket
  # moves to UAT/Releaseable once the PR is merged.
  def tracks_jira_after_merge?
    development? && project.jira? && github_pr_url.present?
  end

  private

  # An errored workflow whose newest local test run started but never finished goes back to it, not to review
  # (also true for a retest after a fix round: earlier completed rounds don't count).
  def local_test_unfinished?
    stages.find_by(stage_type: :local_test)&.local_test_unfinished? || false
  end

  def copy_source
    project.workflows.runbook.find_by(id: copy_stages_from_id) if copy_stages_from_id.present?
  end

  def copy_source_is_a_runbook_of_this_project
    errors.add(:copy_stages_from_id, "must be a runbook workflow of this project") if copy_stages_from_id.present? && copy_source.nil?
  end

  def variable_names_are_placeholders
    bad = variables.keys.grep_v(Prompts::Renderer::VARIABLE_NAME)
    errors.add(:variables, "names must be letters, digits or underscores (#{bad.join(', ')})") if bad.any?
  end

  def jira_development?
    development? && project&.jira?
  end

  def personal_development?
    development? && project&.personal?
  end

  def pr_review_needs_github_project
    errors.add(:base, "PR reviews need a Jira (GitHub-backed) project") unless project&.jira?
  end

  def purge_images
    image_store.purge!
  end

  def seed_stages
    if runbook?
      copy_source&.stages&.each do |source|
        stages.create!(stage_type: :runbook_step, name: source.name, position: source.position,
                       run_mode: source.run_mode, channel: source.channel, prompt: source.prompt,
                       auto_advance: source.auto_advance, wait_for_workflow: source.wait_for_workflow)
      end
    elsif pr_review?
      stages.create!(stage_type: :pr_review)
    elsif project.personal?
      stages.create!(stage_type: :task)
    else
      stages.create!(stage_type: :implementation)
      stages.create!(stage_type: :pr_check)
    end
  end
end
