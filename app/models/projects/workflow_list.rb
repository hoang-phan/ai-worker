# The project dashboard's workflow list: priority order, optional status filter, the ends of the unfiltered list (for
# the move arrows) and logged Jira seconds per ticket (for the time badges).
module Projects
  class WorkflowList
    attr_reader :status_filter

    def initialize(project, status: nil)
      @project = project
      @status_filter = status.presence_in(Workflow.statuses.keys)
    end

    def workflows
      @workflows ||= status_filter ? all_workflows.where(status: status_filter) : all_workflows
    end

    def first_id
      all_workflows.first&.id
    end

    def last_id
      all_workflows.last&.id
    end

    def logged_seconds_for(workflow)
      logged_seconds[workflow.jira_key]
    end

    private

    def all_workflows
      @all_workflows ||= @project.workflows.order(:position, :id)
    end

    def logged_seconds
      @logged_seconds ||= TimeLog.seconds_by_ticket(workflows.filter_map(&:jira_key))
    end
  end
end
