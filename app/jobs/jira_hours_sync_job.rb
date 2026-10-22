# Refreshes the Jira-logged hours stored on every development workflow of the Jira projects.
class JiraHoursSyncJob < ApplicationJob
  queue_as :default

  def perform
    result = Jira::HoursSync.new.call
    Rails.logger.warn("[JiraHoursSyncJob] #{result.failed.join('; ')}") if result.failed.any?
  rescue Jira::WorklogError => e
    Rails.logger.warn("[JiraHoursSyncJob] #{e.message}")
  end
end
