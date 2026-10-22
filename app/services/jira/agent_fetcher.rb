
module Jira
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

    delegate :running?, :last_started_at, to: :run

    def initialize(jira_sync, root: ROOT, run: nil)
      @jira_sync = jira_sync
      @project = jira_sync.project
      @dir = Pathname(root).join(jira_sync.id.to_s)
      @run = run || AiCli::DetachedRun.new(dir: dir, result_name: "tickets.json", stale_after: STALE_AFTER, error_class: FetchError)
    end

    # No-op (returns false) if a fetch process is still alive.
    def start
      run.start(cwd: dir, prompt: prompt)
    end

    # nil while still running (or nothing started); an array of
    # { "key", "summary" } once finished. Raises FetchError on failure.
    def poll
      run.poll { |rows| TicketRows.call(rows) }
    end

    private

    attr_reader :jira_sync, :project, :dir, :run

    def prompt
      Jira::FetchPrompt.new(
        jira_base_url: project.jira_base_url, assignee: project.jira_assignee,
        jira_project: jira_sync.jira_project, parent_ticket: jira_sync.parent_ticket, tickets_file: run.result_path
      ).to_s
    end
  end
end
