# One Jira query for a project: an optional Jira project and/or parent ticket,
# combined with the project's assignee. Both are free text (ID, URL, name...)
# that the agent resolves through the Atlassian MCP. A project can have many.
class JiraSync < ApplicationRecord
  belongs_to :project

  scope :auto, -> { where(auto_sync: true) }

  def label
    [ jira_project.presence && "project #{jira_project}", parent_ticket.presence && "parent #{parent_ticket}" ].compact.join(", ").presence || "all assigned tickets"
  end
end
