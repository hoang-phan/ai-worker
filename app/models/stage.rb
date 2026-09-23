class Stage < ApplicationRecord
  belongs_to :workflow
  belongs_to :prompt_template, optional: true
  has_many :stage_runs, -> { order(created_at: :desc) }, dependent: :destroy

  enum :stage_type, { implementation: 0, pr_check: 1 }
  enum :status, { pending: 0, in_progress: 1, completed: 2, failed: 3 }

  # Falls back to the active default template for this stage's type when
  # no template was explicitly assigned on the stage.
  def effective_template
    prompt_template || PromptTemplate.find_by(stage_type: stage_type, active: true)
  end
end
