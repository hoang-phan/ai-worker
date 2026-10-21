require "fileutils"
require "json"

module Bugsnag
  class FetchError < StandardError; end

  # Triages a Bugsnag project's open errors into Jira Bugs via the agent CLI,
  # which uses the Bugsnag and Atlassian MCP connectors (no tokens in this
  # app). One detached agent run, started in the project's local clone so it
  # can read the code: create tickets, investigate each error read-only, write
  # the cause + fix into the ticket. Same shape as Jira::AgentFetcher: the
  # agent runs detached and writes result.json; `poll` reads it once the
  # process has finished.
  #
  # State lives in tmp/bugsnag_syncs/<id>/: pid, started_at, result.json,
  # agent.log.
  class Triager
    ROOT = Rails.root.join("tmp", "bugsnag_syncs")
    STALE_AFTER = 45.minutes
    # Headless (`claude -p`) can't prompt, so approve exactly what the run
    # needs. No Jira transition/assign/comment tools and no Bash/Edit, so the
    # code stays read-only. MCP server names are whatever the connectors are
    # called in `claude mcp list` (`atlassian`, `bugsnag`/`smartbear`); adjust
    # here if yours differ. Bugsnag is approved server-wide (read tools).
    ALLOWED_TOOLS = %w[
      mcp__atlassian__getAccessibleAtlassianResources
      mcp__atlassian__getVisibleJiraProjects
      mcp__atlassian__getJiraProjectIssueTypesMetadata
      mcp__atlassian__getJiraIssueTypeMetaWithFields
      mcp__atlassian__searchJiraIssuesUsingJql
      mcp__atlassian__getJiraIssue
      mcp__atlassian__createJiraIssue
      mcp__atlassian__editJiraIssue
      mcp__bugsnag
      mcp__smartbear
      Read
      Grep
      Glob
      Write
    ].freeze
    ID = /\A[\w-]{6,64}\z/
    KEY = /\A[A-Z][A-Z0-9]+-\d+\z/

    def initialize(bugsnag_sync)
      @sync = bugsnag_sync
      @project = bugsnag_sync.project
      @dir = ROOT.join(bugsnag_sync.id.to_s)
    end

    def blockers
      list = []
      list << "project kind is not jira" unless project.jira?
      list << "Jira site URL is not set" if project.jira_base_url.blank?
      list << "local directory does not exist" unless Dir.exist?(project.local_directory.to_s)
      list
    end

    def running?
      run.running?
    end

    def last_started_at
      run.last_started_at
    end

    def start
      run.start(cwd: project.local_directory, prompt: prompt, allowed_tools: ALLOWED_TOOLS)
    end

    # nil while running (or nothing started); once finished, the array of
    # { "bugsnag_id", "jira_key" } the agent ticketed. Raises FetchError on failure.
    def poll
      run.poll { |rows| filter(rows) }
    end

    # Merges a poll result into the ledger; returns the newly added keys.
    def import(rows)
      ledger = sync.ledger.dup
      added = rows.filter_map do |row|
        next if ledger.key?(row["bugsnag_id"])

        ledger[row["bugsnag_id"]] = row["jira_key"]
        row["jira_key"]
      end
      sync.update!(ledger: ledger)
      added
    end

    private

    attr_reader :sync, :project, :dir

    def run
      @run ||= AiCli::DetachedRun.new(dir: dir, result_name: "result.json", stale_after: STALE_AFTER, error_class: FetchError)
    end

    def filter(rows)
      rows.filter_map do |row|
        next unless row.is_a?(Hash)

        id = row["bugsnag_id"].to_s.strip
        key = row["jira_key"].to_s.strip
        { "bugsnag_id" => id, "jira_key" => key } if id.match?(ID) && key.match?(KEY)
      end
    end

    def prompt
      TriagePrompt.new(
        repo_full_name: project.repo_full_name, bugsnag_project: sync.bugsnag_project, since: sync.last_synced_at&.iso8601,
        min_events: sync.min_events, max_tickets: sync.max_tickets, jira_base_url: project.jira_base_url,
        jira_project: sync.jira_project, known_ids: sync.ledger, result_file: result_file
      ).to_s
    end

    def result_file
      dir.join("result.json")
    end
  end
end
