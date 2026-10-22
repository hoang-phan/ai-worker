module Jira
  # Pure value object: where (site URL + ticket key) a workflow's Jira worklogs go, and why it can't have any.
  class WorklogTarget
    def initialize(workflow)
      @workflow = workflow
    end

    def base_url
      @workflow.project.jira_base_url
    end

    def key
      @key ||= TicketRef.key_for(@workflow.jira_ticket)
    end

    # nil when the workflow can log time, otherwise the human reason it can't.
    def problem
      project = @workflow.project
      return "only Jira development workflows can log time" unless project.jira? && @workflow.development?
      return "Jira site URL is not set on the project" if base_url.blank?

      "no Jira ticket key found" if key.blank?
    end
  end
end
