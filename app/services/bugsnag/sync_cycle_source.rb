# Adapts one BugsnagSync to AgentRuns::SyncCycle (driven by BugsnagSyncJob).
module Bugsnag
  class SyncCycleSource < AgentRuns::FetcherCycleSource
    RUN_HOUR = 9

    def initialize(bugsnag_sync, sync: nil)
      @bugsnag_sync = bugsnag_sync
      sync ||= Bugsnag::TriageSync.new(bugsnag_sync)
      super(sync:, fetcher: sync.triager)
    end

    def persist!(_result, summary)
      @bugsnag_sync.update(last_synced_at: Time.current, last_result: summary)
    end

    def persist_failure!(message) = @bugsnag_sync.update(last_result: message)
    def eligible? = @bugsnag_sync.auto_sync?

    def due?
      AgentRuns::Cadence.daily_on_weekdays(hour: RUN_HOUR, last_started_at: last_started_at)
    end
  end
end
