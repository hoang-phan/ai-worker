# One Jira worklog entry we created for a workflow's ticket. Also the ledger the day allocation reads:
# totals are global (across every project), not per project.
class TimeLog < ApplicationRecord
  belongs_to :workflow

  validates :ticket_key, :started_at, presence: true
  validates :seconds, numericality: { only_integer: true, greater_than: 0 }
end
