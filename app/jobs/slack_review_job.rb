# Runs every minute. For each project with Slack PR reviews enabled: imports a
# finished agent fetch of Slack mentions (creating PR-review workflows), and
# starts a new fetch when the last one is old enough. The agent runs detached;
# this job never waits on it.
class SlackReviewJob < ApplicationJob
  queue_as :default

  def perform
    Project.jira.where(slack_review_enabled: true).find_each do |project|
      log_prefix = "[SlackReviewJob] project=#{project.id}"
      AgentRuns::SyncCycle.call(
        source: Slack::ReviewCycleSource.new(project),
        log_prefix: log_prefix
      )
    end
  end
end
