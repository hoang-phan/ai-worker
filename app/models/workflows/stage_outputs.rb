module Workflows
  # Query object for what a runbook's stages printed when they succeeded (StageRun action "stage_completed").
  # Failed or started rows never count. Parsing the text stays in Workflows::Variables.
  class StageOutputs
    ACTION = "stage_completed".freeze

    def initialize(workflow)
      @workflow = workflow
    end

    # Every successful output across the workflow's stages, oldest first.
    def all
      completed(StageRun.where(stage_id: workflow.stages.select(:id))).pluck(:output)
    end

    # The newest successful output of one stage (highest id, so tied timestamps are stable), nil when none.
    def latest_for(stage)
      return if stage.nil?

      completed(stage.stage_runs).last&.output
    end

    private

    attr_reader :workflow

    def completed(scope)
      scope.where(action: ACTION).reorder(:id)
    end
  end
end
