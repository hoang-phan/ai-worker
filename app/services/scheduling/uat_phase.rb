module Scheduling
  # UAT tests: a ticket that reached UAT waits out its project's delay (`uat_test_at`), then the agent
  # tests it in a browser. Unlike the post-merge phase this doesn't wait for the scheduler to be idle:
  # a test never touches the git clone and nothing else depends on it, so it only needs a free agent
  # slot (`max_capacity`). A `uat_testing` workflow that isn't running is a failed attempt being retried.
  class UatPhase
    def initialize(queries: WorkflowQueries, execute: ActiveWorkflowRunner::DEFAULT_EXECUTOR,
                   logger: Rails.logger, max_capacity: nil)
      @queries = queries
      @execute = execute
      @logger = logger
      @max_capacity = max_capacity
    end

    def call
      slots = @queries.free_agent_slots(max: max_capacity)
      return if slots <= 0

      @queries.due_uat_tests(limit: slots).each do |workflow|
        workflow.update!(status: :uat_testing) if workflow.uat_waiting?
        execute(workflow)
      end
    end

    private

    def max_capacity
      @max_capacity || WorkflowSchedulerJob.max_concurrent_agents
    end

    def execute(workflow)
      @execute.call(workflow)
    rescue StandardError => e
      @logger.error("[scheduler] workflow=#{workflow.id} #{e.class}: #{e.message}")
    end
  end
end
