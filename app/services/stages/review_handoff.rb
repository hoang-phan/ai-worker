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
      notifier.notify!(
        workflow: workflow, pr_url: pr_url, label: label, reviewers: reviewers, again: again, fixed: fixed,
        thread_ts: thread_ts
      )
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
      workflow.reviewer_list
    end

    private

    attr_reader :workflow, :stage, :project, :notifier, :github

    def review_label(pr_url, title)
      [ workflow.jira_ticket.presence, title ].compact.join(" ").presence || pr_url
    end
  end
end
