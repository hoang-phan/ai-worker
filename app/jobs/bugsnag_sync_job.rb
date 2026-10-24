# Runs every 5 minutes. For each Bugsnag sync: imports a finished agent triage
# run into the ledger, and (for auto-sync ones) starts a new run on weekdays
# once it's past 9 AM and none has started yet today. The agent runs detached;
# this job never waits on it.
class BugsnagSyncJob < ApplicationJob
  queue_as :default

  def perform
    BugsnagSync.includes(:project).find_each do |bugsnag_sync|
      AgentRuns::SyncCycle.call(
        source: Bugsnag::SyncCycleSource.new(bugsnag_sync),
        log_prefix: "[BugsnagSyncJob] bugsnag_sync=#{bugsnag_sync.id}"
      )
    end
  end
end
