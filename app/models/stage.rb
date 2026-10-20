class Stage < ApplicationRecord
  belongs_to :workflow
  belongs_to :prompt_template, optional: true
  has_many :stage_runs, -> { order(created_at: :desc) }, dependent: :destroy

  enum :stage_type, { implementation: 0, pr_check: 1, task: 2, pr_review: 3, jira_update: 4, runbook_step: 5, uat_test: 6, local_test: 7 }

  # Runbook stages only. agent: run the prompt as is. message: post the rendered prompt to Slack `channel`.
  enum :run_mode, { agent: 0, message: 1 }, prefix: :run

  validates :name, presence: true, if: :runbook_step?
  validates :wait_for_workflow, format: { with: /\A[\w.\- ]+\z/, message: "must be a workflow file name or name, e.g. manual_environment_deploy.yml" }, allow_blank: true
  validates :channel, presence: true, if: -> { runbook_step? && run_message? }

  # A started runbook must keep the stage it is currently executing or waiting on.
  def removable?
    workflow.pending? || workflow.current_stage_id != id
  end

  # Action of the newest run, nil when the stage has none. Ordered by id explicitly: the association's default order
  # is created_at desc.
  def last_action
    stage_runs.reorder(id: :desc).first&.action
  end

  # Trailing run of failed/started rows (newest first) with no success or `resumed` in between; counts the failed ones.
  def consecutive_failures
    stage_runs.reorder(id: :desc).pluck(:action)
              .take_while { |action| %w[failed started].include?(action) }
              .count("failed")
  end

  def resolving_conflicts?
    last_action == "conflict_resolution_started"
  end

  def completed_local_test_rounds
    stage_runs.where(action: "local_test_completed").count
  end

  # A local test run that started but whose newest run isn't a completion (earlier completed rounds don't count).
  def local_test_unfinished?
    last = last_action
    last.present? && last != "local_test_completed"
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
end
