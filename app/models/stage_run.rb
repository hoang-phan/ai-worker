class StageRun < ApplicationRecord
  belongs_to :stage

  ACTIONS = %w[
    ran_implementation
    approved_closed
    requested_changes_fixed
    no_action_pending
    failed
  ].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }
end
