class PromptTemplate < ApplicationRecord
  has_many :stages, dependent: :nullify

  enum :stage_type, { implementation: 0, pr_check: 1, task: 2, pr_review: 3, jira_update: 4, runbook_step: 5, uat_test: 6, local_test: 7,
                        ci_check: 8, ci_verify: 9, pr_create: 10, simple_implementation: 11 }

  validates :name, presence: true
  validates :body, presence: true

  PLACEHOLDERS = %w[{JIRA} {PR} {REVIEWER} {SKILLS} {PR_SKILLS} {IMAGES} {TASK} {SLACK} {TESTER} {UAT_URL} {TEST_INSTRUCTIONS} {UAT_INSTRUCTIONS} {LOCAL_URL} {LOCAL_INSTRUCTIONS} {CI_INSTRUCTIONS} {STAGE_NAME} {STARTED_ON} {PREV_OUTPUT}].freeze
end
