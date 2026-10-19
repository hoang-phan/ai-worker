# One Bugsnag project -> Jira project triage. The agent reads open errors,
# files a Jira Bug per new error, investigates the project's local clone
# (read-only) and writes the likely cause / fix into the ticket. Both names are
# free text (name, id, URL, key) that the agent resolves through its MCP
# connectors. `ledger` maps already-ticketed Bugsnag error ids to Jira keys.
class BugsnagSync < ApplicationRecord
  belongs_to :project

  validates :bugsnag_project, :jira_project, presence: true
  validates :min_events, :max_tickets, numericality: { only_integer: true, greater_than: 0 }

  scope :auto, -> { where(auto_sync: true) }

  def label
    "#{bugsnag_project} → #{jira_project}"
  end
end
