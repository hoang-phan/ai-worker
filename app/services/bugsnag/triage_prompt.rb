module Bugsnag
  # Builds the text the Bugsnag triage agent is run with. Takes plain values so it needs neither the DB nor the filesystem.
  class TriagePrompt
    DEFAULT_SINCE = "7 days ago".freeze

    # since: an ISO timestamp, or nil to fall back to DEFAULT_SINCE. known_ids: { bugsnag id => jira key }.
    def initialize(repo_full_name:, bugsnag_project:, since:, min_events:, max_tickets:, jira_base_url:, jira_project:, known_ids:, result_file:)
      @repo_full_name = repo_full_name
      @bugsnag_project = bugsnag_project
      @since = since
      @min_events = min_events
      @max_tickets = max_tickets
      @jira_base_url = jira_base_url
      @jira_project = jira_project
      @known_ids = known_ids
      @result_file = result_file
    end

    def to_s
      since = self.since || DEFAULT_SINCE
      known = known_ids.map { |id, key| "#{id} (#{key})" }.join(", ").presence || "none"
      <<~PROMPT
        You are triaging production errors into Jira tickets. The current directory is the project's code (#{repo_full_name}); read its CLAUDE.md / .agents skills and rules if present. You may create and edit Jira tickets as described below, but NEVER change code, create branches or PRs, or close, transition, assign, comment on or delete tickets. Never change anything in Bugsnag (no status/assignee updates).

        1. Bugsnag: using the Bugsnag MCP tools, resolve the project "#{bugsnag_project}" (name, id or URL). List its OPEN errors first seen or last seen since #{since} with at least #{min_events} events. Skip these Bugsnag error ids, already ticketed: #{known}.
        2. Jira: site #{jira_base_url} (find its Cloud ID with getAccessibleAtlassianResources), project "#{jira_project}" (resolve to the project key), issue type Bug. For each remaining error, search that Jira project for an existing issue containing the Bugsnag error id or URL; if one exists, record it in the result file instead of creating another. Take the top #{max_tickets} errors by event count.
        3. For each, gather only: error class, message, context, top 5 in-app stack frames, event and user counts, first/last seen, release stage, and the Bugsnag link. Create the Bug right away, titled "[Bugsnag] <ErrorClass>: <short message>", with those facts and the Bugsnag error id in the description. Immediately (re)write #{result_file} with every error handled so far as a JSON array like [{"bugsnag_id":"<id>","jira_key":"UNS-12"}] so a crash never loses a created ticket.
        4. Investigate each error in the code (read-only: Read/Grep/Glob). Then update that ticket's description (editJiraIssue) to keep the Bugsnag details and add: Likely cause, Files involved (path:line), Suggested fix, Confidence, Open questions. Keep each section short (about 250 words total).

        If Bugsnag or Jira auth fails or a tool is unavailable, do not guess or work around it: stop, and write nothing to #{result_file} if no ticket was created. If there is nothing new, write [] to #{result_file}. Reply with one short line, e.g. "Recruit triage: 2 tickets (UNS-12, UNS-13)" or "Recruit triage: nothing new".
      PROMPT
    end

    private

    attr_reader :repo_full_name, :bugsnag_project, :since, :min_events, :max_tickets, :jira_base_url, :jira_project, :known_ids, :result_file
  end
end
