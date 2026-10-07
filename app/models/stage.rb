class Stage < ApplicationRecord
  belongs_to :workflow
  belongs_to :prompt_template, optional: true
  has_many :stage_runs, -> { order(created_at: :desc) }, dependent: :destroy

  enum :stage_type, { implementation: 0, pr_check: 1, task: 2 }

  # Falls back to the default template for this stage's type when no
  # template was explicitly assigned on the stage.
  def effective_template
    prompt_template || PromptTemplate.where(stage_type: stage_type).order(:id).first
  end

  def candidate_templates
    PromptTemplate.where(stage_type: stage_type).order(:name)
  end
end
