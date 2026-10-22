# Mirror of one of the JIRA_EMAIL user's Jira worklogs (Jira::HoursSync keeps it in step; Jira::TimeLogger adds the ones
# the app creates). The day allocation and every logged-hours figure read it: totals are global, not per project.
# workflow is the workflow of that ticket, when the app has one.
class TimeLog < ApplicationRecord
  belongs_to :workflow, optional: true

  validates :ticket_key, :started_at, presence: true
  validates :seconds, numericality: { only_integer: true, greater_than: 0 }

  # { ticket_key => total seconds } for the given keys; blank keys are ignored, no keys => {}.
  def self.seconds_by_ticket(keys)
    keys = Array(keys).compact_blank
    return {} if keys.empty?

    where(ticket_key: keys).group(:ticket_key).sum(:seconds)
  end

  def self.seconds_for(key)
    key.blank? ? 0 : where(ticket_key: key).sum(:seconds)
  end
end
