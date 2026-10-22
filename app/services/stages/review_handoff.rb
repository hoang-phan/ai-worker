module Stages
  # Best-effort review handoff work that must never make a completed stage fail.
  class ReviewHandoff
    def initialize(workflow, stage, notifier: Slack::ReviewNotifier.new(workflow.project),
                   github: Github::Client.new(workflow.project))
      @workflow = workflow
      @stage = stage
      @project = workflow.project
      @notifier = notifier
      @github = github
    end

    def notify_reviewers!(again: false, fixed: nil)
      return unless notifier.enabled? && reviewers.any?

      pr_url = workflow.github_pr_url
      title = github.pr_title(pr_url).presence
      label = review_label(pr_url, title)
      notifier.collect(workflow)
      thread_ts = workflow.reload.slack_review_thread_ts.presence
      returned_thread_ts = notifier.notify!(
        workflow: workflow, pr_url: pr_url, label: label, reviewers: reviewers, again: again, fixed: fixed,
        thread_ts: thread_ts
      )
      store_thread_ts(returned_thread_ts) if thread_ts.blank?
      stage.log_run!("slack_review_notified")
    rescue Slack::NotifyError, Github::CommandError => e
      stage.log_run!("slack_review_notify_failed", error: e.message)
    end

    def enable_auto_merge!(pr_url)
      github.enable_auto_merge!(pr_url)
      stage.log_run!("auto_merge_enabled")
    rescue Github::CommandError => e
      stage.log_run!("auto_merge_failed", error: e.message)
    end

    def reviewers
      Github::Client.parse_reviewers(workflow.github_reviewer)
    end

    private

    attr_reader :workflow, :stage, :project, :notifier, :github

    def review_label(pr_url, title)
      [ workflow.jira_ticket.presence, title ].compact.join(" ").presence || pr_url
    end

    # Slack::ReviewNotifier#notify! returns the byte count of its detached-run
    # pid write (an Integer), not a thread timestamp. Only a nonblank String is
    # a usable timestamp, so anything else is ignored here.
    def store_thread_ts(value)
      return unless value.is_a?(String) && value.present?
      return if workflow.slack_review_thread_ts.present?

      workflow.update!(slack_review_thread_ts: value)
    end
  end
end
