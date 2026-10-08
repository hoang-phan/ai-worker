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
    failed
    halted
    resumed
    rolled_back_to_review
  ].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }
end
