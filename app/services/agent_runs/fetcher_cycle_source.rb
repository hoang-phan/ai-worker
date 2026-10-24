# Shared fetcher + sync-wrapper adapter for AgentRuns::SyncCycle. Record-specific
# sources supply persistence, eligibility, cadence, and any hooks.
module AgentRuns
  class FetcherCycleSource < CycleSource
    def initialize(sync:, fetcher:)
      @sync = sync
      @fetcher = fetcher
    end

    def poll = @fetcher.poll
    def import(payload) = @sync.import(payload)
    def summary(result) = result.summary
    def idle? = !@fetcher.running?
    def blockers = @sync.blockers
    def start! = @fetcher.start

    protected

    def last_started_at = @fetcher.last_started_at

    # "<log_prefix> <summary> <failed rows joined by '; '>" for results with a failed list.
    def log_with_failures(log_prefix, result, summary)
      "#{log_prefix} #{summary} #{result.failed.join('; ')}".strip
    end
  end
end
