# Runs every minute. For each project with Slack PR reviews enabled: imports a
# finished agent fetch of Slack mentions (creating PR-review workflows), and
# starts a new fetch when the last one is old enough. The agent runs detached;
# this job never waits on it.
class SlackReviewJob < ApplicationJob
  queue_as :default

  def perform(source_factory: Slack::ReviewCycleSource.method(:new), cycle: AgentRuns::SyncCycle,
              logger: Rails.logger)
    Project.jira.where(slack_review_enabled: true).find_each do |project|
      log_prefix = "[SlackReviewJob] project=#{project.id}"
      cycle.call(
        source: source_factory.call(project),
        log_prefix: log_prefix,
        logger: logger
      )
    end
  end
end
