module Jira
  # Builds the text the Jira ticket-fetch agent is run with. Takes plain values so it needs neither the DB nor the filesystem.
  # The assignee / project / parent values are free text exactly as the user typed them (URL, key, email, full name, ...);
  # the agent resolves them with the Atlassian MCP tools.
  class FetchPrompt
    def initialize(jira_base_url:, assignee:, jira_project:, parent_ticket:, tickets_file:)
      @jira_base_url = jira_base_url
      @assignee = assignee
      @jira_project = jira_project.presence
      @parent_ticket = parent_ticket.presence
      @tickets_file = tickets_file
    end

    def to_s
      <<~PROMPT
        Use the Atlassian (Jira) MCP tools to list Jira issues, then write them to a file. Do not modify anything in Jira.

        Jira site: #{jira_base_url} (find its Cloud ID with getAccessibleAtlassianResources).

        Find every issue that matches ALL of these:
        - Assignee: #{assignee}
          (This may be an account ID, email address, full name, a Jira profile URL, or currentUser(). Resolve it to a Jira account with lookupJiraAccountId / atlassianUserInfo as needed.)
        - Status category: "To Do"
        #{jira_project ? "- In this Jira project: #{jira_project}\n  (This may be a project key such as UNS, a project URL like .../browse/UNS, or a project name. Resolve it to the project key with getVisibleJiraProjects if needed, and use `project = KEY`. This is a Jira project, not a board.)" : ""}
        #{parent_ticket ? "- Child of this parent ticket / epic: #{parent_ticket}\n  (This may be an issue key, a browse URL, or a title. Resolve it to the issue key first.)" : ""}

        Build the JQL yourself and run it with searchJiraIssuesUsingJql, requesting only the key and summary fields, ordered by created ascending, and keep paging until you have every result. If something is ambiguous or cannot be resolved, do NOT guess: skip writing the file.

        Write the result to #{tickets_file} as a JSON array and nothing else, e.g. [{"key":"UIUX-3456","summary":"..."}]. Write [] if there are no matches. If the Jira lookup fails, do NOT create that file. Reply with one short line when done.
      PROMPT
    end

    private

    attr_reader :jira_base_url, :assignee, :jira_project, :parent_ticket, :tickets_file
  end
end
