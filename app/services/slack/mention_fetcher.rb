require "fileutils"
require "json"

module Slack
  class FetchError < StandardError; end

  # Gets the Slack mentions that reference GitHub PRs of a project's repo via
  # the agent CLI, which uses the Slack MCP connector (no Slack token needed).
  # Same shape as Jira::AgentFetcher: the agent runs detached and writes a temp
  # file; `poll` reads it back once the process has finished.
  #
  # State lives in tmp/slack_reviews/<project_id>/: pid, started_at,
  # mentions.json, agent.log.
  class MentionFetcher
    ROOT = Rails.root.join("tmp", "slack_reviews")
    STALE_AFTER = 15.minutes
    # Look back this far on the first run; later runs start at the previous
    # fetch (minus a margin — import is idempotent, so overlap is harmless).
    FIRST_LOOKBACK = 1.day
    OVERLAP = 1.hour
    # Headless (`claude -p`) can't prompt, so approve exactly what the fetch
    # needs: Slack read/search tools and writing mentions.json. Nothing that
    # posts, reacts or edits in Slack is listed, so those calls are denied.
    ALLOWED_TOOLS = %w[
      mcp__claude_ai_Slack__slack_search_public_and_private
      mcp__claude_ai_Slack__slack_search_public
      mcp__claude_ai_Slack__slack_search_users
      mcp__claude_ai_Slack__slack_search_channels
      mcp__claude_ai_Slack__slack_read_thread
      mcp__claude_ai_Slack__slack_read_channel
      mcp__claude_ai_Slack__slack_read_user_profile
      Write
    ].freeze

    def initialize(project)
      @project = project
      @dir = ROOT.join(project.id.to_s)
    end

    def running?
      run.running?
    end

    def last_started_at
      run.last_started_at
    end

    # No-op (returns false) if a fetch process is still alive.
    def start
      since = last_started_at ? last_started_at - OVERLAP : FIRST_LOOKBACK.ago
      run.start(cwd: dir, prompt: prompt(since), allowed_tools: ALLOWED_TOOLS)
    end

    # nil while still running (or nothing started); an array of
    # { "slack_url", "pr_urls" } once finished. Raises FetchError on failure.
    def poll
      run.poll { |rows| filter(rows) }
    end

    private

    attr_reader :project, :dir

    def run
      @run ||= AiCli::DetachedRun.new(dir: dir, result_name: "mentions.json", stale_after: STALE_AFTER, error_class: FetchError)
    end

    def filter(rows)
      rows.filter_map do |row|
        next unless row.is_a?(Hash)

        slack_url = row["slack_url"].to_s.strip
        pr_urls = Array(row["pr_urls"]).map { |url| url.to_s.strip }.select { |url| url.match?(ReviewSync::PR_URL) }
        { "slack_url" => slack_url, "pr_urls" => pr_urls.uniq } if slack_url.present? && pr_urls.any?
      end
    end

    # `slack_mention` is free text exactly as the user typed it (@handle, user
    # ID, user group, ...); the agent resolves it with the Slack MCP tools.
    def prompt(since)
      <<~PROMPT
        Use the Slack MCP tools to find Slack messages that mention #{project.slack_mention}, then write what you find to a file. Do not post, react to, or modify anything in Slack.
        (The mention may be a @handle, a user ID, a user group, or a name. Resolve it to the right Slack user / group first, and search public and private channels you can access.)

        Only consider messages posted after #{since.utc.iso8601}.

        Ignore messages generated automatically by the GitHub app (or any other bot/app), e.g. the end-of-day recap / digest messages that list virtually every open PR, PR notifications and reminders. Only consider messages written by real people who are asking for a review. Do not collect PRs from such automated messages, and do not take PRs from them when reading a thread either.

        For each such message, collect the GitHub pull-request URLs of the repository #{project.repo_full_name} (https://github.com/#{project.repo_full_name}/pull/<number>) that belong to the request: those in the message itself, or in other messages of the thread it belongs to (read the thread with the thread-reading tool). Ignore PRs of other repositories and PRs that are only mentioned in quoted history or link previews of unrelated discussion. Skip messages that end up with no PR.

        Write the result to #{mentions_file} as a JSON array and nothing else, e.g. [{"slack_url":"https://workspace.slack.com/archives/C123/p1700000000000100","pr_urls":["https://github.com/#{project.repo_full_name}/pull/42"]}]. slack_url is the permalink of the message that mentions #{project.slack_mention}. Write [] if there are none. If the Slack lookup fails, do NOT create that file. Reply with one short line when done.
      PROMPT
    end

    def mentions_file
      dir.join("mentions.json")
    end
  end
end
