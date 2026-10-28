# Refreshes the Jira-logged hours stored on every development workflow of the Jira projects.
class JiraHoursSyncJob < ApplicationJob
  queue_as :default

  def perform(sync: Jira::HoursSync.new, logger: Rails.logger)
    result = sync.call
    logger.warn("[JiraHoursSyncJob] #{result.failed.join('; ')}") if result.failed.any?
  rescue Jira::WorklogError => e
    logger.warn("[JiraHoursSyncJob] #{e.message}")
  end
end
