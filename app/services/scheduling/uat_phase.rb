module Scheduling
  # UAT tests: a ticket that reached UAT waits out its project's delay (`uat_test_at`), then the agent
  # tests it in a browser. Unlike the post-merge phase this doesn't wait for the scheduler to be idle:
  # a test never touches the git clone and nothing else depends on it, so it only needs a free agent
  # slot (`max_capacity`). A `uat_testing` workflow that isn't running is a failed attempt being retried.
  class UatPhase
    attr_reader :max_capacity

    def initialize(queries: WorkflowQueries, execute: CurrentStageExecutor.new,
                   logger: Rails.logger, max_capacity: nil, clock: -> { Time.current })
      @queries = queries
      @guarded_executor = GuardedExecutor.new(executor: execute, logger: logger)
      @max_capacity = max_capacity
      @clock = clock
    end

    def call
      slots = @queries.free_agent_slots(max: @max_capacity || Capacity.default_max)
      return if slots <= 0

      @queries.due_uat_tests(limit: slots, now: @clock.call).each do |workflow|
        workflow.update!(status: :uat_testing) if workflow.uat_waiting?
        @guarded_executor.call(workflow)
      end
    end
  end
end
