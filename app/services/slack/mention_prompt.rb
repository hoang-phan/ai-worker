module Slack
  # Builds the text the Slack mention-fetch agent is run with. Takes plain values so it needs neither the DB nor the filesystem.
  # `mention` is free text exactly as the user typed it (@handle, user ID, user group, ...); the agent resolves it with the Slack MCP tools.
  class MentionPrompt
    def initialize(mention:, repo_full_name:, since:, mentions_file:)
      @mention = mention
      @repo_full_name = repo_full_name
      @since = since
      @mentions_file = mentions_file
    end

    def to_s
      <<~PROMPT
        Use the Slack MCP tools to find Slack messages that mention #{mention}, then write what you find to a file. Do not post, react to, or modify anything in Slack.
        (The mention may be a @handle, a user ID, a user group, or a name. Resolve it to the right Slack user / group first, and search public and private channels you can access.)

        Only consider messages posted after #{since.utc.iso8601}.

        Ignore messages generated automatically by the GitHub app (or any other bot/app), e.g. the end-of-day recap / digest messages that list virtually every open PR, PR notifications and reminders. Only consider messages written by real people who are asking for a review. Do not collect PRs from such automated messages, and do not take PRs from them when reading a thread either.

        For each such message, collect the GitHub pull-request URLs of the repository #{repo_full_name} (https://github.com/#{repo_full_name}/pull/<number>) that belong to the request: those in the message itself, or in other messages of the thread it belongs to (read the thread with the thread-reading tool). Ignore PRs of other repositories and PRs that are only mentioned in quoted history or link previews of unrelated discussion. Skip messages that end up with no PR.

        Write the result to #{mentions_file} as a JSON array and nothing else, e.g. [{"slack_url":"https://workspace.slack.com/archives/C123/p1700000000000100","pr_urls":["https://github.com/#{repo_full_name}/pull/42"]}]. slack_url is the permalink of the message that mentions #{mention}. Write [] if there are none. If the Slack lookup fails, do NOT create that file. Reply with one short line when done.
      PROMPT
    end

    private

    attr_reader :mention, :repo_full_name, :since, :mentions_file
  end
end
