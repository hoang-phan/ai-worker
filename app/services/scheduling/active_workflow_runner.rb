module Scheduling
  # One scheduler tick's pass over in-flight workflows: polls running ones first (so finished runs free
  # their slot/clone), then starts eligible waiting ones within Capacity. One workflow's failure is
  # logged and never stops the rest of the tick.
  class ActiveWorkflowRunner
    def self.stage_executor(executor_class: StageExecutor)
      lambda do |workflow|
        stage = workflow.current_stage
        executor_class.new(workflow, stage).call if stage
      end
    end

    # Default executor: runs the workflow's current stage, if any.
    DEFAULT_EXECUTOR = stage_executor

    def initialize(queries: WorkflowQueries, executor: ActiveWorkflowRunner.stage_executor, logger: Rails.logger, max_capacity: nil)
      @queries = queries
      @guarded_executor = GuardedExecutor.new(executor: executor, logger: logger)
      @max_capacity = max_capacity
    end

    def call(run_workflow_id = nil)
      active_workflows = @queries.active
      # A Jira update (`merged`) or a UAT test (`uat_testing`) that's mid-run is polled like any other run.
      workflows = active_workflows + @queries.polling_updates
      return if workflows.empty?

      running, waiting = workflows.partition(&:processing?)
      waiting = Planner.eligible_waiting(active_workflows: active_workflows, waiting: waiting, run_workflow_id: run_workflow_id)

      running.each { |workflow| @guarded_executor.call(workflow) }

      capacity = Capacity.new(busy_clones: @queries.busy_clone_keys, max: @max_capacity || Capacity.default_max)

      waiting.each do |workflow|
        next unless capacity.can_start?(workflow)

        @guarded_executor.call(workflow)
        capacity.started!(workflow) if workflow.reload.processing?
      end
    end
  end
end
