class StageRun < ApplicationRecord
  belongs_to :stage

  ACTIONS = %w[
    started
    ran_implementation
    auto_merge_enabled
    auto_merge_failed
    approved_closed
    pr_merged_closed
    conflict_resolution_started
    conflicts_resolved
    requested_changes_fixed
    no_action_pending
    checks_failing
    task_completed
    review_completed
    pr_not_open_skipped
    pr_merged_detected
    merge_check_failed
    jira_updated
    failed
    halted
    resumed
    rolled_back_to_review
    stage_completed
    message_sent
    advanced
    waiting_for_check
    check_passed
    uat_test_scheduled
    uat_test_completed
    local_test_completed
    local_test_failing
    local_test_retest_scheduled
    local_test_rounds_exhausted
  ].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }
end
