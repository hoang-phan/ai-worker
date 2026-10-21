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

    def prompt
      Jira::FetchPrompt.new(
        jira_base_url: project.jira_base_url, assignee: project.jira_assignee,
        jira_project: jira_sync.jira_project, parent_ticket: jira_sync.parent_ticket, tickets_file: tickets_file
      ).to_s
    end

    def tickets_file
      dir.join("tickets.json")
    end
  end
end
