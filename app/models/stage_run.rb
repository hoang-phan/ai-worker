class StageRun < ApplicationRecord
  belongs_to :stage

  ACTIONS = %w[
    started
    ran_implementation
    auto_merge_enabled
    auto_merge_failed
    slack_review_notified
    slack_review_notify_failed
    approved_closed
    pr_merged_closed
    conflict_resolution_started
    conflicts_resolved
    requested_changes_fixed
    no_action_pending
    checks_failing
    task_completed
    task_pushed
    task_push_failed
    follow_ups_created
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
    ci_check_completed
    ci_verify_passed
    ci_verify_failed
    ci_rounds_exhausted
    pr_created
  ].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }

  # A workflow's stage run history, newest first; id breaks created_at ties so the order is deterministic.
  scope :history_for, ->(workflow) {
    joins(:stage).where(stages: { workflow_id: workflow.id }).reorder(created_at: :desc, id: :desc)
  }
end
