# Runs every minute. For each project with Slack PR reviews enabled: imports a
# finished agent fetch of Slack mentions (creating PR-review workflows), and
# starts a new fetch when the last one is old enough. The agent runs detached;
# this job never waits on it.
class SlackReviewJob < ApplicationJob
  queue_as :default

  FETCH_EVERY = 30.minutes

  def perform
    Project.jira.where(slack_review_enabled: true).find_each do |project|
      sync = Slack::ReviewSync.new(project)
      fetcher = sync.fetcher

      mentions = fetcher.poll
      record(project, sync.import(mentions)) if mentions

      next if fetcher.running?
      next if fetcher.last_started_at && fetcher.last_started_at > FETCH_EVERY.ago

      blockers = sync.blockers
      if blockers.any?
        Rails.logger.warn("[SlackReviewJob] project=#{project.id} blocked: #{blockers.join('; ')}")
      else
        fetcher.start
      end
    rescue Slack::FetchError, AiCli::CommandError => e
      Rails.logger.error("[SlackReviewJob] project=#{project.id} #{e.message}")
      project.update(slack_last_result: "failed: #{e.message}".truncate(250))
    end
  end

  private

  def record(project, result)
    skipped = "skipped #{result.skipped.size}"
    skipped += " (#{result.skipped_reasons.map { |reason, count| "#{count} #{reason}" }.join(", ")})" if result.skipped_reasons.any?
    summary = "created #{result.created.size}, #{skipped}, failed #{result.failed.size}"
    Rails.logger.info("[SlackReviewJob] project=#{project.id} #{summary} #{result.failed.join('; ')}".strip)
    project.update(slack_last_synced_at: Time.current, slack_last_result: summary)
    # Don't wait for the scheduler's next */5 cron tick: start the new reviews now.
    WorkflowSchedulerJob.perform_later if result.created.any?
  end
end
