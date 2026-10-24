class Stage < ApplicationRecord
  belongs_to :workflow
  belongs_to :prompt_template, optional: true
  has_many :stage_runs, -> { order(created_at: :desc) }, dependent: :destroy

  # Persisted integers: append, never renumber or reorder. PromptTemplate reuses this mapping.
  STAGE_TYPES = { implementation: 0, pr_check: 1, task: 2, pr_review: 3, jira_update: 4, runbook_step: 5, uat_test: 6, local_test: 7,
                  ci_check: 8, ci_verify: 9, pr_create: 10, simple_implementation: 11 }.freeze

  enum :stage_type, STAGE_TYPES

  # Runbook stages only. agent: run the prompt as is. message: post the rendered prompt to Slack `channel`.
  enum :run_mode, { agent: 0, message: 1 }, prefix: :run

  validates :name, presence: true, if: :runbook_step?
  validates :wait_for_workflow, format: { with: /\A[\w.\- ]+\z/, message: "must be a workflow file name or name, e.g. manual_environment_deploy.yml" }, allow_blank: true
  validates :channel, presence: true, if: -> { runbook_step? && run_message? }

  delegate :last_action, :consecutive_failures, :resolving_conflicts?, :completed_local_test_rounds, :completed_ci_rounds,
           :local_test_unfinished?, to: :run_history

  # A started runbook must keep the stage it is currently executing or waiting on.
  def removable?
    workflow.pending? || workflow.current_stage_id != id
  end

  # Records one audit-log row for this stage; `action` must be in StageRun::ACTIONS (raises RecordInvalid otherwise).
  def log_run!(action, output: nil, error: nil)
    stage_runs.create!(action: action, output: output, error: error)
  end

  def display_name
    name.presence || stage_type.humanize
  end

  # Falls back to the default template for this stage's type when no
  # template was explicitly assigned on the stage.
  def effective_template
    prompt_template || PromptTemplate.where(stage_type: stage_type).order(:id).first
  end

  def candidate_templates
    PromptTemplate.where(stage_type: stage_type).order(:name)
  end

  private

  # Built per call, never memoized: log_run! followed by a read must see the new row. Ordered by id explicitly: the
  # association's default order is created_at desc.
  def run_history
    Stages::RunHistory.new(stage_runs.reorder(id: :desc).pluck(:action))
  end
end
