# Adapts one JiraSync to AgentRuns::SyncCycle (driven by JiraSyncJob).
module Jira
  class SyncCycleSource < AgentRuns::CycleSource
    FETCH_EVERY = 3.hours

    def initialize(jira_sync, log_prefix:, sync: nil)
      @jira_sync = jira_sync
      @log_prefix = log_prefix
      @sync = sync || Jira::TicketSync.new(jira_sync)
      @fetcher = @sync.fetcher
    end

    def poll = @fetcher.poll
    def import(issues) = @sync.import(issues)
    def summary(result) = result.summary

    def log_message(result, summary)
      "#{@log_prefix} #{summary} #{result.failed.join('; ')}".strip
    end

    def persist!(_result, summary)
      @jira_sync.update(last_synced_at: Time.current, last_result: summary)
    end

    def persist_failure!(message) = @jira_sync.update(last_result: message)
    def eligible? = @jira_sync.auto_sync?
    def idle? = !@fetcher.running?

    def due?
      AgentRuns::Cadence.every(FETCH_EVERY, last_started_at: @fetcher.last_started_at)
    end

    def blockers = @sync.blockers
    def start! = @fetcher.start
  end
end
