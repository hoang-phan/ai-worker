module Jira
  # Creates a pending workflow for every "To Do" Jira ticket assigned to the
  # project's configured user, narrowed by the sync's Jira project / parent ticket (free text the agent resolves).
  # Idempotent: a ticket that already has a workflow in this project (in any
  # status) is skipped.
  class TicketSync
    Result = Struct.new(:blockers, :created, :skipped, :failed, keyword_init: true) do
      def summary
        "created #{created.size}, skipped #{skipped.size}, failed #{failed.size}"
      end
    end

    def initialize(jira_sync, fetcher: nil)
      @jira_sync = jira_sync
      @project = jira_sync.project
      @fetcher = fetcher
    end

    # Everything that would stop workflows from being created automatically.
    def blockers
      Projects::RunBlockers.new(project).messages(:jira_kind, :jira_site_url, :assignee, :default_reviewers)
    end

    def fetcher
      @fetcher ||= AgentFetcher.new(jira_sync)
    end

    # `issues` is the array AgentFetcher#poll returns.
    def import(issues)
      found = blockers
      return empty_result(found) if found.any?

      result = empty_result
      existing = existing_keys
      issues.each { |issue| import_issue(issue, existing, result) }
      result
    end

    private

    attr_reader :jira_sync, :project

    def existing_keys
      keys = project.workflows.pluck(:jira_ticket).filter_map { |t| TicketRef.key_for(t) }
      Set.new(keys)
    end

    def empty_result(blockers = [])
      Result.new(blockers: blockers, created: [], skipped: [], failed: [])
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
