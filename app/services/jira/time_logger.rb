module Jira
  # Logs time for a workflow's Jira ticket: picks the next available day/time, creates the worklog in Jira,
  # then records it in the local ledger (so a failed Jira call leaves no phantom time behind).
  # An unestimated ticket (original estimate blank or 0) gets the logged time as its original estimate.
  class TimeLogger
    PRESET_HOURS = [ 0.5, 1, 1.5, 2 ].freeze

    def initialize(client_factory: ->(base_url) { WorklogClient.new(base_url) }, planner: TimeSlotPlanner.new)
      @client_factory = client_factory
      @planner = planner
    end

    # Raises Jira::WorklogError when the workflow can't be logged or Jira rejects it.
    def log(workflow, hours)
      target = WorklogTarget.new(workflow)
      raise WorklogError, "#{workflow.label}: #{target.problem}" if target.problem

      key = target.key
      seconds = (hours.to_f * 3600).round
      started_at = @planner.next_start(seconds)
      client = @client_factory.call(target.base_url)
      worklog_id = client.add_worklog(key, started_at: started_at, seconds: seconds)
      time_log = workflow.time_logs.create!(ticket_key: key, started_at: started_at, seconds: seconds, jira_worklog_id: worklog_id)
      apply_estimate(client, key, seconds)
      time_log
    end

    private

    # Best effort: the time is already logged, so a failed estimate update must not fail (or hide) the log.
    def apply_estimate(client, key, seconds)
      client.set_original_estimate_if_blank(key, seconds)
    rescue WorklogError => e
      Rails.logger.warn("Jira original estimate for #{key} not updated: #{e.message}")
    end
  end
end
