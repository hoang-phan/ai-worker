module Scheduling
  # Merged PRs are only processed when the scheduler is otherwise idle: nothing implementing or
  # running an agent (workflows merely waiting on review count as idle). First `done` workflows
  # whose PR got merged become `merged`, then one `merged` workflow at a time gets its Jira ticket
  # updated (the run is polled by ActiveWorkflowRunner on later ticks, and holds the idle check
  # shut until it finishes). One workflow's failure is logged and never stops the rest.
  class PostMergePhase
    DEFAULT_GITHUB_FACTORY = ->(project) { Github::Client.new(project) }

    def initialize(queries: WorkflowQueries, execute: CurrentStageExecutor.new,
                   github_factory: DEFAULT_GITHUB_FACTORY, logger: Rails.logger)
      @queries = queries
      @guarded_executor = GuardedExecutor.new(executor: execute, logger: logger)
      @github_factory = github_factory
      @logger = logger
    end

    def call
      return if @queries.work_in_progress?

      confirm_merges
      workflow = @queries.next_merged
      @guarded_executor.call(workflow) if workflow
    end

    private

    def confirm_merges
      @queries.merge_candidates.each do |workflow|
        next unless workflow.tracks_jira_after_merge?

        pr_check = workflow.stages.find_by(stage_type: :pr_check)
        next unless pr_check

        Stages::MergeCheck.new(workflow: workflow, stage: pr_check, github: @github_factory.call(workflow.project)).call
      rescue StandardError => e
        @logger.error("[scheduler] merge check workflow=#{workflow.id} #{e.class}: #{e.message}")
      end
    end
  end
end
