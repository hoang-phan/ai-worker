# Shared fetcher + sync-wrapper adapter for AgentRuns::SyncCycle. Record-specific
# sources supply persistence, eligibility, cadence, and any hooks.
module AgentRuns
  class FetcherCycleSource < CycleSource
    def initialize(sync:, fetcher:, clock: -> { Time.current })
      @sync = sync
      @fetcher = fetcher
      @clock = clock
    end

    def poll = @fetcher.poll
    def import(payload) = @sync.import(payload)
    def summary(result) = result.summary
    def idle? = !@fetcher.running?
    def blockers = @sync.blockers
    def start! = @fetcher.start

    protected

    def last_started_at = @fetcher.last_started_at
    def now = @clock.call

    # Suffix for sources whose results carry a failed list: the rows joined by '; '.
    def failed_detail(result) = result.failed.join("; ")
  end
end
