module Scheduling
  # Default scheduler executor: runs the workflow's current stage, if any.
  class CurrentStageExecutor
    def initialize(executor_class: StageExecutor)
      @executor_class = executor_class
    end

    def call(workflow)
      stage = workflow.current_stage
      @executor_class.new(workflow, stage).call if stage
    end
  end
end
