# Adapts one Project's Slack PR reviews to AgentRuns::SyncCycle (driven by SlackReviewJob).
module Slack
  class ReviewCycleSource < AgentRuns::FetcherCycleSource
    FETCH_EVERY = 30.minutes

    def initialize(project, log_prefix:, sync: nil)
      @project = project
      @log_prefix = log_prefix
      sync ||= Slack::ReviewSync.new(project)
      super(sync:, fetcher: sync.fetcher)
    end

    def log_message(result, summary)
      "#{@log_prefix} #{summary} #{result.failed.join('; ')}".strip
    end

    def persist!(_result, summary)
      @project.update(slack_last_synced_at: Time.current, slack_last_result: summary)
    end

    def persist_failure!(message) = @project.update(slack_last_result: message)

    # Don't wait for the scheduler's next */5 cron tick: start the new reviews now.
    def after_import(result)
      WorkflowSchedulerJob.perform_later if result.created.any?
    end

    def due?
      AgentRuns::Cadence.every(FETCH_EVERY, last_started_at: last_started_at)
    end
  end
end
