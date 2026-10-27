# Adapts one JiraSync to AgentRuns::SyncCycle (driven by JiraSyncJob).
module Jira
  class SyncCycleSource < AgentRuns::FetcherCycleSource
    FETCH_EVERY = 3.hours
    RESCUE_ERRORS = [ Jira::FetchError, AiCli::CommandError ].freeze

    def initialize(jira_sync, sync: nil, clock: -> { Time.current })
      @jira_sync = jira_sync
      sync ||= Jira::TicketSync.new(jira_sync)
      super(sync:, fetcher: sync.fetcher, clock:)
    end

    def log_detail(result) = failed_detail(result)

    def persist!(_result, summary)
      @jira_sync.update(last_synced_at: now, last_result: summary)
    end

    def persist_failure!(message) = @jira_sync.update(last_result: message)
    def rescue_errors = RESCUE_ERRORS
    def eligible? = @jira_sync.auto_sync?

    def due?
      AgentRuns::Cadence.every(FETCH_EVERY, last_started_at: last_started_at, now:)
    end
  end
end
