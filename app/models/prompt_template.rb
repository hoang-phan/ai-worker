class PromptTemplate < ApplicationRecord
  has_many :stages, dependent: :nullify

  enum :stage_type, Stage::STAGE_TYPES

  validates :name, presence: true
  validates :body, presence: true

  PLACEHOLDERS = %w[{JIRA} {PR} {REVIEWER} {SKILLS} {PR_SKILLS} {IMAGES} {TASK} {SLACK} {TESTER} {UAT_URL} {TEST_INSTRUCTIONS} {UAT_INSTRUCTIONS} {LOCAL_URL} {LOCAL_INSTRUCTIONS} {CI_INSTRUCTIONS} {STAGE_NAME} {STARTED_ON} {PREV_OUTPUT}].freeze
end
