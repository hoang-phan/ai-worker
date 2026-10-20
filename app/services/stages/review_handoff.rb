module Stages
  # Best-effort review handoff work that must never make a completed stage fail.
  class ReviewHandoff
    def initialize(workflow, stage)
      @workflow = workflow
      @stage = stage
      @project = workflow.project
    end

    def notify_reviewers!(again: false, fixed: nil)
      notifier = Slack::ReviewNotifier.new(project)
      return unless notifier.enabled? && reviewers.any?

      pr_url = workflow.github_pr_url
      title = Github::Client.new(project).pr_title(pr_url).presence
      label = [ workflow.jira_ticket.presence, title ].compact.join(" ").presence || pr_url
      notifier.collect(workflow)
      thread_ts = workflow.reload.slack_review_thread_ts.presence
      returned_thread_ts = notifier.notify!(
        workflow: workflow, pr_url: pr_url, label: label, reviewers: reviewers, again: again, fixed: fixed,
        thread_ts: thread_ts
      )
      store_thread_ts(returned_thread_ts) if thread_ts.blank?
      log(action: "slack_review_notified")
    rescue Slack::NotifyError, Github::CommandError => e
      log(action: "slack_review_notify_failed", error: e.message)
    end

    def enable_auto_merge!(pr_url)
      Github::Client.new(project).enable_auto_merge!(pr_url)
      log(action: "auto_merge_enabled")
    rescue Github::CommandError => e
      log(action: "auto_merge_failed", error: e.message)
    end

    def reviewers
      Github::Client.parse_reviewers(workflow.github_reviewer)
    end

    private

    attr_reader :workflow, :stage, :project

    # Slack::ReviewNotifier currently returns the byte count from writing its
    # detached-run pid. A synchronous notifier may return a thread timestamp,
    # so accept only a nonblank String and leave the asynchronous collector's
    # established behavior intact.
    def store_thread_ts(value)
      return unless value.is_a?(String) && value.present?
      return if workflow.slack_review_thread_ts.present?

      workflow.update!(slack_review_thread_ts: value)
    end

    def log(action:, output: nil, error: nil)
      stage.stage_runs.create!(action: action, output: output, error: error)
    end
  end
end
