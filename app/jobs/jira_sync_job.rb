# Runs every minute. For each Jira sync: imports a finished agent fetch, and
# (for auto-sync ones) starts a new fetch when the last one is old enough.
# The agent runs detached; this job never waits on it.
class JiraSyncJob < ApplicationJob
  queue_as :default

  def perform(source_factory: Jira::SyncCycleSource.method(:new), cycle: AgentRuns::SyncCycle,
              logger: Rails.logger)
    JiraSync.includes(:project).find_each do |jira_sync|
      project = jira_sync.project
      next unless project.jira_site?

      log_prefix = "[JiraSyncJob] jira_sync=#{jira_sync.id}"
      cycle.call(
        source: source_factory.call(jira_sync),
        log_prefix: log_prefix,
        logger: logger
      )
    end
  end
end
