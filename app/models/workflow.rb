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

  # Development workflows not started yet. Brainstorming only adds more once none are left; every other status is
  # irrelevant to it (implementing ones are shown to the agent so it doesn't repeat them, done ones are in the code).
  QUEUED_STATUSES = %w[pending].freeze
  SUMMARY_LENGTH = 100
  # Columns cleared when an agent run finishes or fails; merge into the workflow's next update!.
  AI_RUN_RESET = { processing: false, ai_pid: nil, ai_log_path: nil, ai_started_at: nil, ai_log_offset: 0, ai_provider: nil }.freeze

  scope :queued, -> { development.where(status: QUEUED_STATUSES) }

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

  # The agent CLI this workflow runs with. Precedence: the rotation provider picked by AiCli::Rotation the first time
  # one is needed (pinned per workflow for its life); else nil, meaning the app-wide AiCli::AgentSetting applies.
  def rotation_provider!
    return rotation_provider if rotation_provider.present?

    provider = AiCli::Rotation.next_provider
    update_column(:rotation_provider, provider) if provider
    provider
  end

  validates_with Workflows::Validator
  validates :github_pr_url, format: { with: %r{\Ahttps://github\.com/[^/\s]+/[^/\s]+/pull/\d+\z}, message: "must be a github.com pull request URL" }, allow_blank: true

  # Create-time only: id of another runbook workflow of the project whose stages this one starts with.
  attr_accessor :copy_stages_from_id

  after_create { Workflows::StageSeeder.new(self).call }
  after_destroy :purge_images

  # Reference images are plain files on disk; see Workflows::ImageStore.
  def image_store
    Workflows::ImageStore.new(workflow_id: id)
  end

  delegate :dir, :paths, to: :image_store, prefix: :image

  # `uploads` are ActionDispatch::Http::UploadedFile objects. Returns the number saved.
  def add_images(uploads) = image_store.add(uploads)

  def remove_image(name) = image_store.remove(name)

  # Position for a stage appended after this workflow's existing ones.
  def next_stage_position
    (stages.maximum(:position) || 0) + 1
  end

  # comma-separated skill names entered in the UI, rendered into the {SKILLS} placeholder
  def skill_list
    comma_list(skills)
  end

  # Same format as `skills`, rendered into {PR_SKILLS}: the skills only the PR stage uses (e.g. PR description writing).
  def pr_skill_list
    comma_list(pr_skills)
  end

  # `github_reviewer` holds one or more usernames, separated by commas and/or whitespace.
  def reviewer_list
    github_reviewer.to_s.split(/[,\s]+/).reject(&:blank?).uniq
  end

  # brief / heading text lives in Workflows::Label.
  delegate :brief, :heading, to: :workflow_label

  # "org/repo#123" for PR-review workflows, otherwise the Jira ticket / task.
  def label = workflow_label.value

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

  # Ends an agent run: clears the ai_* run columns (AI_RUN_RESET) and applies attrs in the same update.
  def finish_ai_run!(**attrs) = update!(AI_RUN_RESET.merge(attrs))

  # The manual lifecycle transitions live in Workflows::Transitions.
  delegate :start!, :resume!, :resume_status, :can_rollback_to_review?, :rollback_to_review!, :can_run_stage?,
           :request_stage_run!, :can_advance?, to: :transitions

  # The runbook state machine lives in Workflows::RunbookNavigator.
  def start_runbook! = runbook_navigator.start!

  def advance! = runbook_navigator.advance!

  def next_runbook_stage = runbook_navigator.next_stage

  def previous_runbook_stage = runbook_navigator.previous_stage

  def current_stage = Workflows::CurrentStage.new(self).call

  # Development workflows on a project set up for local testing: the PR goes to local testing before review.
  def local_test_before_review?
    development? && project.local_test_ready?
  end

  # Where a workflow goes once its PR is up and checked.
  def post_pr_status
    local_test_before_review? ? :local_testing : :reviewing
  end

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

  # Built per call, not memoized: Transitions reads live state.
  def transitions = Workflows::Transitions.new(self)

  def workflow_label = Workflows::Label.new(self)

  def runbook_navigator = Workflows::RunbookNavigator.new(self)

  def comma_list(value)
    value.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def stage_outputs
    Workflows::StageOutputs.new(self).all
  end

  def purge_images
    image_store.purge!
  end
end
