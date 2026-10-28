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

  def jira_key = Jira::TicketRef.key_for(jira_ticket)

  # Seconds the Jira user has logged on this workflow's ticket (mirrored in time_logs).
  def logged_seconds = TimeLog.seconds_for(jira_key)

  def slack_review_thread_ts=(value); super(Slack::ThreadRef.ts_for(value)); end

  validates_with Workflows::Validator
  validates :github_pr_url, format: { with: %r{\Ahttps://github\.com/[^/\s]+/[^/\s]+/pull/\d+\z}, message: "must be a github.com pull request URL" }, allow_blank: true

  # Create-time only: id of another runbook workflow of the project whose stages this one starts with.
  attr_accessor :copy_stages_from_id

  after_create { Workflows::StageSeeder.new(self).call }
  after_destroy :purge_images

  # Reference images are plain files on disk; see Workflows::ImageStore.
  def image_store = Workflows::ImageStore.new(workflow_id: id)

  delegate :dir, :paths, to: :image_store, prefix: :image

  # `uploads` are ActionDispatch::Http::UploadedFile objects. Returns the number saved.
  def add_images(uploads) = image_store.add(uploads)

  def remove_image(name) = image_store.remove(name)

  # Position for a stage appended after this workflow's existing ones.
  def next_stage_position = (stages.maximum(:position) || 0) + 1

  delegate :skill_list, :pr_skill_list, :reviewer_list, to: :setting_lists

  # brief / heading text lives in Workflows::Label.
  delegate :brief, :heading, to: :workflow_label

  # "org/repo#123" for PR-review workflows, otherwise the Jira ticket / task.
  def label = workflow_label.value

  def variables = super || {}

  delegate :output_variable_names, :input_variables, :variables_text, :variables_text=, to: :variable_set

  # Ends an agent run: clears the ai_* run columns (AI_RUN_RESET) and applies attrs in the same update.
  def finish_ai_run!(**attrs) = update!(AI_RUN_RESET.merge(attrs))

  # The manual lifecycle transitions live in Workflows::Transitions.
  delegate :start!, :resume!, :resume_status, :can_rollback_to_review?, :rollback_to_review!, :can_run_stage?,
           :can_skip_stage?, :skip_stage!, :request_stage_run!, :can_advance?, to: :transitions

  # The runbook state machine lives in Workflows::RunbookNavigator.
  delegate :start_runbook!, :advance!, :next_runbook_stage, :previous_runbook_stage, to: :runbook_actions

  def current_stage = Workflows::CurrentStage.new(self).call

  # Development workflows on a project set up for local testing: the PR goes to local testing before review.
  def local_test_before_review? = development? && project.local_test_ready?

  # Where a workflow goes once its PR is up and checked.
  def post_pr_status = local_test_before_review? ? :local_testing : :reviewing

  # Jira-project development workflows that got a PR: the ones whose ticket
  # moves to UAT/Releaseable once the PR is merged.
  def tracks_jira_after_merge? = development? && project.jira? && github_pr_url.present?

  # The runbook this one's stages are copied from at creation (nil when none was chosen or it isn't valid).
  def copy_source = copy_stages_from_id.present? ? project.workflows.runbook.find_by(id: copy_stages_from_id) : nil

  private

  # Built per call, not memoized: Transitions reads live state.
  def transitions = Workflows::Transitions.new(self)

  def workflow_label = Workflows::Label.new(self)

  def variable_set = Workflows::VariableSet.new(self)

  def setting_lists = Workflows::SettingLists.new(self)

  def runbook_navigator = Workflows::RunbookNavigator.new(self)

  def runbook_actions = Workflows::RunbookActions.new(runbook_navigator)

  def purge_images = image_store.purge!
end
