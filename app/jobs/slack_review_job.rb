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

      AgentRuns::SyncCycle.call(
        log_prefix: "[SlackReviewJob] project=#{project.id}",
        rescue_errors: [ Slack::FetchError, AiCli::CommandError ],
        poll: -> { fetcher.poll },
        import: ->(mentions) { sync.import(mentions) },
        summary: ->(result) { summarize(result) },
        log_message: ->(result, summary) { "[SlackReviewJob] project=#{project.id} #{summary} #{result.failed.join('; ')}".strip },
        persist: ->(_result, summary) { project.update(slack_last_synced_at: Time.current, slack_last_result: summary) },
        # Don't wait for the scheduler's next */5 cron tick: start the new reviews now.
        after_import: ->(result) { WorkflowSchedulerJob.perform_later if result.created.any? },
        idle: -> { !fetcher.running? },
        due: -> { fetcher.last_started_at.nil? || fetcher.last_started_at <= FETCH_EVERY.ago },
        blockers: -> { sync.blockers },
        start: -> { fetcher.start },
        persist_failure: ->(message) { project.update(slack_last_result: message) }
      )
    end
  end

  private

  def summarize(result)
    skipped = "skipped #{result.skipped.size}"
    skipped += " (#{result.skipped_reasons.map { |reason, count| "#{count} #{reason}" }.join(", ")})" if result.skipped_reasons.any?
    "created #{result.created.size}, #{skipped}, failed #{result.failed.size}"
  end
end
