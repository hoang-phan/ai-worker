# Runs every 5 minutes. For each Bugsnag sync: imports a finished agent triage
# run into the ledger, and (for auto-sync ones) starts a new run on weekdays
# once it's past 9 AM and none has started yet today. The agent runs detached;
# this job never waits on it.
class BugsnagSyncJob < ApplicationJob
  queue_as :default

  RUN_HOUR = 9

  def perform
    BugsnagSync.includes(:project).find_each do |bugsnag_sync|
      triager = Bugsnag::Triager.new(bugsnag_sync)

      AgentRuns::SyncCycle.call(
        log_prefix: "[BugsnagSyncJob] bugsnag_sync=#{bugsnag_sync.id}",
        rescue_errors: [ Bugsnag::FetchError, AiCli::CommandError ],
        poll: -> { triager.poll },
        import: ->(rows) { triager.import(rows) },
        summary: ->(added) { Bugsnag::Triager.summary(added) },
        persist: ->(_added, summary) { bugsnag_sync.update(last_synced_at: Time.current, last_result: summary) },
        eligible: -> { bugsnag_sync.auto_sync? },
        due: -> { AgentRuns::Cadence.daily_on_weekdays(hour: RUN_HOUR, last_started_at: triager.last_started_at) },
        idle: -> { !triager.running? },
        blockers: -> { triager.blockers },
        start: -> { triager.start },
        persist_failure: ->(message) { bugsnag_sync.update(last_result: message) }
      )
    end
  end
end
