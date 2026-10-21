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
      project = workflow.project
      raise WorklogError, "#{workflow.label}: only Jira development workflows can log time" unless project.jira? && workflow.development?
      raise WorklogError, "#{workflow.label}: Jira site URL is not set on the project" if project.jira_base_url.blank?

      key = TicketRef.key_for(workflow.jira_ticket)
      raise WorklogError, "#{workflow.label}: no Jira ticket key found" if key.blank?

      seconds = (hours.to_f * 3600).round
      started_at = @planner.next_start(seconds)
      worklog_id = @client_factory.call(project.jira_base_url).add_worklog(key, started_at: started_at, seconds: seconds)
      workflow.time_logs.create!(ticket_key: key, started_at: started_at, seconds: seconds, jira_worklog_id: worklog_id)
    end
  end
end
