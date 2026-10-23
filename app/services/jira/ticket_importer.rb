module Jira
  # Creates a pending workflow for every Jira issue whose ticket key has no
  # workflow in the project yet (in any status). Blank keys are ignored and a
  # key repeated within one batch is skipped.
  class TicketImporter
    def initialize(project)
      @project = project
    end

    # `issues` is the array AgentFetcher#poll returns; fills and returns `result`.
    def import(issues, result)
      existing = existing_keys
      issues.each { |issue| import_issue(issue, existing, result) }
      result
    end

    private

    attr_reader :project

    def existing_keys
      keys = project.workflows.pluck(:jira_ticket).filter_map { |t| TicketRef.key_for(t) }
      Set.new(keys)
    end

    def import_issue(issue, existing, result)
      key = issue["key"]
      return if key.blank?

      if existing.include?(key)
        result.skipped << key
      else
        create_workflow(issue, result)
        existing << key
      end
    end

    def workflow_attributes(key)
      url = TicketRef.url_for(project.jira_base_url, key)
      Projects::WorkflowDefaults.new(project).attributes(kind: :development).merge(jira_ticket: url, branch_name: TicketRef.branch_name_for(url))
    end

    def create_workflow(issue, result)
      workflow = project.workflows.new(workflow_attributes(issue["key"]))
      if workflow.save
        result.created << issue["key"]
      else
        result.failed << "#{issue['key']}: #{workflow.errors.full_messages.to_sentence}"
      end
    end
  end
end
