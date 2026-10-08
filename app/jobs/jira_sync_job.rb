# Runs every minute. For each Jira sync: imports a finished agent fetch, and
# (for auto-sync ones) starts a new fetch when the last one is old enough.
# The agent runs detached; this job never waits on it.
class JiraSyncJob < ApplicationJob
  queue_as :default

  FETCH_EVERY = 3.hours

  def perform
    JiraSync.includes(:project).find_each do |jira_sync|
      project = jira_sync.project
      next unless project.jira? && project.jira_base_url.present?

      sync = Jira::TicketSync.new(jira_sync)
      fetcher = sync.fetcher

      issues = fetcher.poll
      record(jira_sync, sync.import(issues)) if issues

      next unless jira_sync.auto_sync? && !fetcher.running?
      next if fetcher.last_started_at && fetcher.last_started_at > FETCH_EVERY.ago

      blockers = sync.blockers
      if blockers.any?
        Rails.logger.warn("[JiraSyncJob] jira_sync=#{jira_sync.id} blocked: #{blockers.join('; ')}")
      else
        fetcher.start
      end
    rescue Jira::FetchError, AiCli::CommandError => e
      Rails.logger.error("[JiraSyncJob] jira_sync=#{jira_sync.id} #{e.message}")
      jira_sync.update(last_result: "failed: #{e.message}".truncate(250))
    end
  end

  private

  def record(jira_sync, result)
    summary = "created #{result.created.size}, skipped #{result.skipped.size}, failed #{result.failed.size}"
    Rails.logger.info("[JiraSyncJob] jira_sync=#{jira_sync.id} #{summary} #{result.failed.join('; ')}".strip)
    jira_sync.update(last_synced_at: Time.current, last_result: summary)
  end
end
