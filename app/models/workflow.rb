class Workflow < ApplicationRecord
  belongs_to :project
  has_many :stages, -> { order(:position, :id) }, dependent: :destroy
  has_many :time_logs, dependent: :destroy

  enum :status, { pending: 0, implementing: 1, reviewing: 2, done: 3, errored: 4, merged: 5, jira_updated: 6, waiting: 7,
                 uat_waiting: 8, uat_testing: 9, uat_tested: 10, local_testing: 11, ci_checking: 12, ci_verifying: 13,
                 opening_pr: 14 }

  # development: a Jira ticket / personal task we implement ourselves.
  # pr_review: someone else's PR (found in a Slack mention) that we review.
  # runbook: a deploy/release-style run with its own ordered stages (any project can have many),
  # paused for a person (Next) after each.
  enum :kind, { development: 0, pr_review: 1, runbook: 2 }

  def jira_key
    Jira::TicketRef.key_for(jira_ticket)
  end

  # Seconds the Jira user has logged on this workflow's ticket (mirrored in time_logs).
  def logged_seconds
    TimeLog.seconds_for(jira_key)
  end

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

  after_create { Workflows::StageSeeder.new(self).call }
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

  # Same format as `skills`, rendered into {PR_SKILLS}: the skills only the PR stage uses (e.g. PR description writing).
  def pr_skill_list
    pr_skills.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  # One short line for compact listings (the brainstorm agent's backlog), however the workflow was made.
  def brief
    Workflows::Label.new(self).brief
  end

  # "org/repo#123" for PR-review workflows, otherwise the Jira ticket / task.
  def label
    Workflows::Label.new(self).value
  end

  # The page heading on the workflow show screen.
  def heading
    Workflows::Label.new(self).heading
  end

  def variables
    super || {}
  end

  # Names a stage produced at run time (`VAR: NAME=value` in its output), as opposed to inputs the user typed.
  def output_variable_names
    Workflows::Variables.output_names(stage_outputs)
  end

  # The variables the user set up front (channel, CSS group …), without anything a stage emitted.
  def input_variables
    Workflows::Variables.input_only(variables, stage_outputs)
  end

  # Edited in the UI as one `NAME=value` per line.
  def variables_text
    Workflows::Variables.to_text(variables)
  end

  def variables_text=(text)
    self.variables = Workflows::Variables.parse(text)
  end

  # The manual lifecycle transitions live in Workflows::Transitions.
  def start! = Workflows::Transitions.new(self).start!

  def resume! = Workflows::Transitions.new(self).resume!

  def resume_status = Workflows::Transitions.new(self).resume_status

  def can_rollback_to_review? = Workflows::Transitions.new(self).can_rollback_to_review?

  def rollback_to_review! = Workflows::Transitions.new(self).rollback_to_review!

  def can_run_stage? = Workflows::Transitions.new(self).can_run_stage?

  def request_stage_run! = Workflows::Transitions.new(self).request_stage_run!

  def can_advance? = Workflows::Transitions.new(self).can_advance?

  # The runbook state machine lives in Workflows::RunbookNavigator.
  def start_runbook! = Workflows::RunbookNavigator.new(self).start!

  def advance! = Workflows::RunbookNavigator.new(self).advance!

  def next_runbook_stage = Workflows::RunbookNavigator.new(self).next_stage

  def previous_runbook_stage = Workflows::RunbookNavigator.new(self).previous_stage

  def current_stage = Workflows::CurrentStage.new(self).call

  # Jira-project development workflows that got a PR: the ones whose ticket
  # moves to UAT/Releaseable once the PR is merged.
  def tracks_jira_after_merge?
    development? && project.jira? && github_pr_url.present?
  end

  # The runbook this one's stages are copied from at creation (nil when none was chosen or it isn't valid).
  def copy_source
    project.workflows.runbook.find_by(id: copy_stages_from_id) if copy_stages_from_id.present?
  end

  private

  def stage_outputs
    StageRun.where(stage_id: stages.select(:id), action: "stage_completed").pluck(:output)
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
end
