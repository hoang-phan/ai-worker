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

      TicketImporter.new(project).import(issues, empty_result)
    end

    private

    attr_reader :jira_sync, :project

    def empty_result(blockers = [])
      Result.new(blockers: blockers, created: [], skipped: [], failed: [])
    end
  end
end
