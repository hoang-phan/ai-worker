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

    def initialize(jira_sync)
      @jira_sync = jira_sync
      @project = jira_sync.project
    end

    # Everything that would stop workflows from being created automatically.
    def blockers
      list = []
      list << "project kind is not jira" unless project.jira?
      list << "Jira site URL is not set" if project.jira_base_url.blank?
      list << "assignee is not set" if project.jira_assignee.blank?
      list << "default GitHub reviewers are not set (workflows require a reviewer)" if project.default_reviewers.blank?
      list
    end

    def fetcher
      AgentFetcher.new(jira_sync)
    end

    # `issues` is the array AgentFetcher#poll returns.
    def import(issues)
      found = blockers
      return Result.new(blockers: found, created: [], skipped: [], failed: []) if found.any?

      result = Result.new(blockers: [], created: [], skipped: [], failed: [])
      existing = existing_keys
      issues.each do |issue|
        key = issue["key"]
        next if key.blank?

        if existing.include?(key)
          result.skipped << key
        else
          create_workflow(issue, result)
          existing << key
        end
      end
      result
    end

    private

    attr_reader :jira_sync, :project

    def existing_keys
      keys = project.workflows.pluck(:jira_ticket).filter_map { |t| TicketRef.key_for(t) }
      Set.new(keys)
    end

    def create_workflow(issue, result)
      url = TicketRef.url_for(project.jira_base_url, issue["key"])
      workflow = project.workflows.new(
        jira_ticket: url,
        branch_name: TicketRef.branch_name_for(url),
        github_reviewer: project.default_reviewers,
        skills: project.default_skills,
        pr_skills: project.default_pr_skills,
        position: project.next_workflow_position
      )
      if workflow.save
        result.created << issue["key"]
      else
        result.failed << "#{issue['key']}: #{workflow.errors.full_messages.to_sentence}"
      end
    end
  end
end
