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

      rows = triager.poll
      record(bugsnag_sync, triager.import(rows)) if rows

      next unless bugsnag_sync.auto_sync? && due?(triager) && !triager.running?

      blockers = triager.blockers
      if blockers.any?
        Rails.logger.warn("[BugsnagSyncJob] bugsnag_sync=#{bugsnag_sync.id} blocked: #{blockers.join('; ')}")
      else
        triager.start
      end
    rescue Bugsnag::FetchError, AiCli::CommandError => e
      Rails.logger.error("[BugsnagSyncJob] bugsnag_sync=#{bugsnag_sync.id} #{e.message}")
      bugsnag_sync.update(last_result: "failed: #{e.message}".truncate(250))
    end
  end

  private

  def due?(triager)
    now = Time.zone.now
    return false if now.saturday? || now.sunday? || now.hour < RUN_HOUR

    triager.last_started_at.nil? || triager.last_started_at < now.beginning_of_day
  end

  def record(bugsnag_sync, added)
    summary = added.any? ? "#{added.size} new ticket(s): #{added.join(', ')}" : "nothing new"
    Rails.logger.info("[BugsnagSyncJob] bugsnag_sync=#{bugsnag_sync.id} #{summary}")
    bugsnag_sync.update(last_synced_at: Time.current, last_result: summary)
  end
end
