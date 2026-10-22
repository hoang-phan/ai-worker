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
      run.poll { |rows| MentionRows.call(rows) }
    end

    private

    attr_reader :project, :dir

    def run
      @run ||= AiCli::DetachedRun.new(dir: dir, result_name: "mentions.json", stale_after: STALE_AFTER, error_class: FetchError)
    end

    def prompt(since)
      Slack::MentionPrompt.new(
        mention: project.slack_mention, repo_full_name: project.repo_full_name, since: since, mentions_file: mentions_file
      ).to_s
    end

    def mentions_file
      dir.join("mentions.json")
    end
  end
end
