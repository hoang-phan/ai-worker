module Jira
  # Reads the hours currently logged in Jira for a workflow's ticket.
  class LoggedTime
    def initialize(client_factory: ->(base_url) { WorklogClient.new(base_url) })
      @client_factory = client_factory
    end

    # nil when the workflow has no loggable Jira target. Raises Jira::WorklogError when Jira fails.
    def seconds_for(workflow)
      target = WorklogTarget.new(workflow)
      return if target.problem

      @client_factory.call(target.base_url).logged_seconds(target.key)
    end
  end
end
