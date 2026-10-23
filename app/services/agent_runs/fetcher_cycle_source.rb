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
  end
end
