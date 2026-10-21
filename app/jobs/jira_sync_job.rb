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

      AgentRuns::SyncCycle.call(
        log_prefix: "[JiraSyncJob] jira_sync=#{jira_sync.id}",
        rescue_errors: [ Jira::FetchError, AiCli::CommandError ],
        poll: -> { fetcher.poll },
        import: ->(issues) { sync.import(issues) },
        summary: ->(result) { result.summary },
        log_message: ->(result, summary) { "[JiraSyncJob] jira_sync=#{jira_sync.id} #{summary} #{result.failed.join('; ')}".strip },
        persist: ->(_result, summary) { jira_sync.update(last_synced_at: Time.current, last_result: summary) },
        eligible: -> { jira_sync.auto_sync? },
        idle: -> { !fetcher.running? },
        due: -> { AgentRuns::Cadence.every(FETCH_EVERY, last_started_at: fetcher.last_started_at) },
        blockers: -> { sync.blockers },
        start: -> { fetcher.start },
        persist_failure: ->(message) { jira_sync.update(last_result: message) }
      )
    end
  end
end
