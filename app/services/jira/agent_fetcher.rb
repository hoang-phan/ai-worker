require "fileutils"
require "json"

module Jira
  class FetchError < StandardError; end

  # Gets a project's matching Jira tickets via the agent CLI, which uses the
  # Atlassian MCP connector (no Jira API token needed). The agent runs
  # detached, like stage runs, and writes the tickets to a temp file;
  # `poll` reads that file back once the process has finished.
  #
  # State lives in tmp/jira_sync/<jira_sync_id>/: pid, started_at, tickets.json,
  # agent.log.
  class AgentFetcher
    ROOT = Rails.root.join("tmp", "jira_sync")
    STALE_AFTER = 15.minutes
    KEY = /\A[A-Z][A-Z0-9]+-\d+\z/

    def initialize(jira_sync)
      @jira_sync = jira_sync
      @project = jira_sync.project
      @dir = ROOT.join(jira_sync.id.to_s)
    end

    def running?
      run.running?
    end

    def last_started_at
      run.last_started_at
    end

    # No-op (returns false) if a fetch process is still alive.
    def start
      run.start(cwd: dir, prompt: prompt)
    end

    # nil while still running (or nothing started); an array of
    # { "key", "summary" } once finished. Raises FetchError on failure.
    def poll
      run.poll { |rows| filter(rows) }
    end

    private

    attr_reader :jira_sync, :project, :dir

    def run
      @run ||= AiCli::DetachedRun.new(dir: dir, result_name: "tickets.json", stale_after: STALE_AFTER, error_class: FetchError)
    end

    def filter(rows)
      rows.filter_map do |row|
        key = row.is_a?(Hash) ? row["key"].to_s.strip : nil
        { "key" => key, "summary" => row["summary"].to_s } if key&.match?(KEY)
      end
    end

    # The assignee / project / parent values are free text exactly as the user
    # typed them (URL, key, email, full name, ...); the agent resolves them
    # with the Atlassian MCP tools.
    def prompt
      jira_project = jira_sync.jira_project.presence
      parent = jira_sync.parent_ticket.presence
      <<~PROMPT
        Use the Atlassian (Jira) MCP tools to list Jira issues, then write them to a file. Do not modify anything in Jira.

        Jira site: #{project.jira_base_url} (find its Cloud ID with getAccessibleAtlassianResources).

        Find every issue that matches ALL of these:
        - Assignee: #{project.jira_assignee}
          (This may be an account ID, email address, full name, a Jira profile URL, or currentUser(). Resolve it to a Jira account with lookupJiraAccountId / atlassianUserInfo as needed.)
        - Status category: "To Do"
        #{jira_project ? "- In this Jira project: #{jira_project}\n  (This may be a project key such as UNS, a project URL like .../browse/UNS, or a project name. Resolve it to the project key with getVisibleJiraProjects if needed, and use `project = KEY`. This is a Jira project, not a board.)" : ""}
        #{parent ? "- Child of this parent ticket / epic: #{parent}\n  (This may be an issue key, a browse URL, or a title. Resolve it to the issue key first.)" : ""}

        Build the JQL yourself and run it with searchJiraIssuesUsingJql, requesting only the key and summary fields, ordered by created ascending, and keep paging until you have every result. If something is ambiguous or cannot be resolved, do NOT guess: skip writing the file.

        Write the result to #{tickets_file} as a JSON array and nothing else, e.g. [{"key":"UIUX-3456","summary":"..."}]. Write [] if there are no matches. If the Jira lookup fails, do NOT create that file. Reply with one short line when done.
      PROMPT
    end

    def tickets_file
      dir.join("tickets.json")
    end
  end
end
