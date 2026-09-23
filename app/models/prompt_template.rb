class PromptTemplate < ApplicationRecord
  has_many :stages, dependent: :nullify

  enum :stage_type, { implementation: 0, pr_check: 1 }

  validates :name, presence: true
  validates :body, presence: true

  # Only one active default template per stage_type at a time.
  before_save :deactivate_siblings, if: :active?

  PLACEHOLDERS = %w[{JIRA} {PR} {REVIEWER} {SKILLS}].freeze

  private

  def deactivate_siblings
    self.class.where(stage_type: stage_type).where.not(id: id).update_all(active: false)
  end
end
