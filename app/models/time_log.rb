# Mirror of one of the JIRA_EMAIL user's Jira worklogs (Jira::HoursSync keeps it in step; Jira::TimeLogger adds the ones
# the app creates). The day allocation and every logged-hours figure read it: totals are global, not per project.
# workflow is the workflow of that ticket, when the app has one.
class TimeLog < ApplicationRecord
  belongs_to :workflow, optional: true

  validates :ticket_key, :started_at, presence: true
  validates :seconds, numericality: { only_integer: true, greater_than: 0 }
end
