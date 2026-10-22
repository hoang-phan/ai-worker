require "fileutils"

module Slack
  class NotifyError < StandardError; end

  # Posts a one-line "please review" message to the project's Slack channel once a PR is up for review,
  # tagging the Slack users that map to the PR's GitHub reviewers (Project#slack_user_map). Optional:
  # needs a channel on the project. The message is posted by a short detached agent run through the Slack MCP
  # connector, so it comes from the connected Slack user rather than from an app/bot.
  #
  # The run can't hand the message's thread id back synchronously. It prints the message's permalink instead;
  # `collect` (called by SlackPingJob and before the next ping) reads it back into Workflow#slack_review_thread_ts.
  #
  # State lives in tmp/slack_pings/<workflow_id>/<started_at>/: pid, agent.log.
  class ReviewNotifier
    ROOT = Rails.root.join("tmp", "slack_pings")
    STALE_AFTER = 5.minutes
    MODEL = ENV.fetch("SLACK_PING_MODEL", "haiku")
    PERMALINK = %r{https://[^\s/]+\.slack\.com/archives/[A-Z0-9]+/p\d{16}(?:\?\S*)?}
    # Headless (`claude -p`) can't prompt: approve only the one tool that posts.
    ALLOWED_TOOLS = %w[mcp__claude_ai_Slack__slack_send_message].freeze

    def initialize(project, runner: AiCli::Runner, clock: -> { Time.current }, root: ROOT)
      @project = project
      @runner = runner
      @clock = clock
      @root = Pathname(root)
    end

    def enabled?
      project.slack_review_channel.present?
    end

    # Why notifications can't be sent right now, for the UI.
    def blockers
      project.slack_review_channel.blank? ? [ "Slack channel is not set" ] : []
    end

    # See Slack::ReviewMessage#text.
    def message(pr_url:, label:, reviewers:, again: false, fixed: nil)
      review_message(pr_url: pr_url, label: label, reviewers: reviewers, again: again, fixed: fixed).text
    end

    # Starts the posting run and returns immediately. Posts into `thread_ts` when given (a re-request replies in
    # the original thread), otherwise as a new channel message. Returns nil: starts the run; the thread id is
    # collected later by PingCollector.
    def notify!(workflow:, pr_url:, label:, reviewers:, again: false, fixed: nil, thread_ts: nil)
      raise NotifyError, blockers.join("; ") unless enabled?

      msg = review_message(pr_url: pr_url, label: label, reviewers: reviewers, again: again, fixed: fixed)
      prompt = msg.prompt(channel: project.slack_review_channel, thread_ts: thread_ts)
      spawn(run_dir(workflow), prompt)
      nil
    rescue AiCli::CommandError, SystemCallError => e
      raise NotifyError, "Slack ping failed to start: #{e.message}"
    end

    # Reads back finished pings of `workflow` (see PingCollector). Returns true while a ping is still running.
    def collect(workflow)
      PingCollector.new.collect(workflow)
    end

    private

    attr_reader :project, :runner, :clock, :root

    # tmp/slack_pings/<workflow_id>/<started_at>/, the layout PingCollector reads back.
    def run_dir(workflow)
      root.join(workflow.id.to_s, clock.call.to_i.to_s)
    end

    def spawn(dir, prompt)
      FileUtils.mkdir_p(dir)
      pid = runner.start(dir.to_s, prompt, log_path: dir.join("agent.log").to_s,
                         allowed_tools: ALLOWED_TOOLS, model: MODEL)
      dir.join("pid").write(pid)
    end

    def review_message(pr_url:, label:, reviewers:, again:, fixed:)
      ReviewMessage.new(pr_url: pr_url, label: label, reviewers: reviewers, again: again, fixed: fixed,
                        slack_id_for: project.method(:slack_user_id_for))
    end
  end
end
