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
