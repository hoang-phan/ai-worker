# Runs every 5 minutes. For each Bugsnag sync: imports a finished agent triage
# run into the ledger, and (for auto-sync ones) starts a new run on weekdays
# once it's past 9 AM and none has started yet today. The agent runs detached;
# this job never waits on it.
class BugsnagSyncJob < ApplicationJob
  queue_as :default

  def perform(source_factory: Bugsnag::SyncCycleSource.method(:new), cycle: AgentRuns::SyncCycle,
              logger: Rails.logger)
    BugsnagSync.includes(:project).find_each do |bugsnag_sync|
      cycle.call(
        source: source_factory.call(bugsnag_sync),
        log_prefix: "[BugsnagSyncJob] bugsnag_sync=#{bugsnag_sync.id}",
        logger: logger
      )
    end
  end
end
