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
        summary: ->(added) { added.any? ? "#{added.size} new ticket(s): #{added.join(', ')}" : "nothing new" },
        persist: ->(_added, summary) { bugsnag_sync.update(last_synced_at: Time.current, last_result: summary) },
        eligible: -> { bugsnag_sync.auto_sync? },
        due: -> { due?(triager) },
        idle: -> { !triager.running? },
        blockers: -> { triager.blockers },
        start: -> { triager.start },
        persist_failure: ->(message) { bugsnag_sync.update(last_result: message) }
      )
    end
  end

  private

  def due?(triager)
    now = Time.zone.now
    return false if now.saturday? || now.sunday? || now.hour < RUN_HOUR

    triager.last_started_at.nil? || triager.last_started_at < now.beginning_of_day
  end
end
