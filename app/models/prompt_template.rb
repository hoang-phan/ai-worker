class PromptTemplate < ApplicationRecord
  has_many :stages, dependent: :nullify

  enum :stage_type, { implementation: 0, pr_check: 1, task: 2 }

  validates :name, presence: true
  validates :body, presence: true

  PLACEHOLDERS = %w[{JIRA} {PR} {REVIEWER} {SKILLS} {TASK}].freeze
end
