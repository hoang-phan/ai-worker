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
      since = sync.last_synced_at ? sync.last_synced_at.iso8601 : "7 days ago"
      known = sync.ledger.map { |id, key| "#{id} (#{key})" }.join(", ").presence || "none"
      <<~PROMPT
        You are triaging production errors into Jira tickets. The current directory is the project's code (#{project.repo_full_name}); read its CLAUDE.md / .agents skills and rules if present. You may create and edit Jira tickets as described below, but NEVER change code, create branches or PRs, or close, transition, assign, comment on or delete tickets. Never change anything in Bugsnag (no status/assignee updates).

        1. Bugsnag: using the Bugsnag MCP tools, resolve the project "#{sync.bugsnag_project}" (name, id or URL). List its OPEN errors first seen or last seen since #{since} with at least #{sync.min_events} events. Skip these Bugsnag error ids, already ticketed: #{known}.
        2. Jira: site #{project.jira_base_url} (find its Cloud ID with getAccessibleAtlassianResources), project "#{sync.jira_project}" (resolve to the project key), issue type Bug. For each remaining error, search that Jira project for an existing issue containing the Bugsnag error id or URL; if one exists, record it in the result file instead of creating another. Take the top #{sync.max_tickets} errors by event count.
        3. For each, gather only: error class, message, context, top 5 in-app stack frames, event and user counts, first/last seen, release stage, and the Bugsnag link. Create the Bug right away, titled "[Bugsnag] <ErrorClass>: <short message>", with those facts and the Bugsnag error id in the description. Immediately (re)write #{result_file} with every error handled so far as a JSON array like [{"bugsnag_id":"<id>","jira_key":"UNS-12"}] so a crash never loses a created ticket.
        4. Investigate each error in the code (read-only: Read/Grep/Glob). Then update that ticket's description (editJiraIssue) to keep the Bugsnag details and add: Likely cause, Files involved (path:line), Suggested fix, Confidence, Open questions. Keep each section short (about 250 words total).

        If Bugsnag or Jira auth fails or a tool is unavailable, do not guess or work around it: stop, and write nothing to #{result_file} if no ticket was created. If there is nothing new, write [] to #{result_file}. Reply with one short line, e.g. "Recruit triage: 2 tickets (UNS-12, UNS-13)" or "Recruit triage: nothing new".
      PROMPT
    end

    def result_file
      dir.join("result.json")
    end
  end
end
