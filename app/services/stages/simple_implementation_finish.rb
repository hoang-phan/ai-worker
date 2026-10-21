module Stages
  # The success path of a simple_implementation run (ci_loop flow): the work is committed and there is no PR yet, so
  # the workflow moves on to the check stage.
  class SimpleImplementationFinish
    def initialize(workflow:, stage:)
      @workflow = workflow
      @stage = stage
    end

    def call(output)
      workflow.update!(Workflow::AI_RUN_RESET.merge(status: :ci_checking))
      stage.log_run!("ran_implementation", output: output)
    end

    private

    attr_reader :workflow, :stage
  end
end
