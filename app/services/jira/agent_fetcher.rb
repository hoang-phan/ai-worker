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

    # True only while the agent process is actually alive. A leftover pid
    # file from a finished or killed process doesn't count; `poll` still
    # picks it up to import the result.
    def running?
      pid_file.exist? && AiCli::Runner.poll(pid_file.read.to_i) == :running
    end

    def last_started_at
      started_file.exist? ? Time.zone.at(started_file.read.to_f) : nil
    end

    # No-op (returns false) if a fetch process is still alive. A stale pid
    # file from a dead process is overwritten (any unimported result is
    # discarded).
    def start
      return false if running?

      FileUtils.mkdir_p(dir)
      FileUtils.rm_f(tickets_file)
      pid = AiCli::Runner.start(dir.to_s, prompt, log_path: log_file.to_s)
      pid_file.write(pid)
      started_file.write(Time.current.to_f)
      true
    end

    # nil while still running (or nothing started); an array of
    # { "key", "summary" } once finished. Raises FetchError on failure.
    def poll
      return unless pid_file.exist?

      if AiCli::Runner.poll(pid_file.read.to_i) == :running
        return unless stale?

        clear
        raise FetchError, "agent did not finish within #{STALE_AFTER.inspect}"
      end

      clear
      read_tickets
    end

    private

    attr_reader :jira_sync, :project, :dir

    def stale?
      last_started_at.nil? || last_started_at < STALE_AFTER.ago
    end

    def clear
      FileUtils.rm_f(pid_file)
    end

    def read_tickets
      raise FetchError, "agent wrote no #{tickets_file.basename}; see #{log_file}" unless tickets_file.exist?

      data = JSON.parse(tickets_file.read)
      raise FetchError, "#{tickets_file.basename} is not a JSON array" unless data.is_a?(Array)

      data.filter_map do |row|
        key = row.is_a?(Hash) ? row["key"].to_s.strip : nil
        { "key" => key, "summary" => row["summary"].to_s } if key&.match?(KEY)
      end
    rescue JSON::ParserError => e
      raise FetchError, "invalid JSON in #{tickets_file.basename}: #{e.message}"
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

    def pid_file
      dir.join("pid")
    end
    def started_file
      dir.join("started_at")
    end
    def tickets_file
      dir.join("tickets.json")
    end
    def log_file
      dir.join("agent.log")
    end
  end
end
