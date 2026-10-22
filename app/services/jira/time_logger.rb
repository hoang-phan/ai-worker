module Jira
  # Logs time for a workflow's Jira ticket: picks the next available day/time, creates the worklog in Jira,
  # then records it in the local ledger (so a failed Jira call leaves no phantom time behind).
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
      worklog_id = @client_factory.call(target.base_url).add_worklog(key, started_at: started_at, seconds: seconds)
      workflow.time_logs.create!(ticket_key: key, started_at: started_at, seconds: seconds, jira_worklog_id: worklog_id)
    end
  end
end
