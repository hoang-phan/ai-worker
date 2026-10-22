module Stages
  # The success path of uat_test: the agent commented the verdict on the ticket. The AiCli::CommandError raised here
  # for a missing result marker propagates to StageExecutor's rescue.
  class UatTestFinish
    def initialize(workflow:, stage:)
      @workflow = workflow
      @stage = stage
    end

    # The prompt makes the agent end with `UAT_RESULT: PASSED|FAILED|BLOCKED` once its comment is on the ticket. Any of
    # the three is a finished test (the verdict lives in the comment and this log); no line means we can't tell the
    # comment was posted, so the stage fails and retries like any other.
    def call(output)
      result = AiCli::Output.new(output).uat_result
      raise AiCli::CommandError, "agent finished without a UAT_RESULT line, treating the UAT test as failed" unless result

      workflow.finish_ai_run!(status: :uat_tested)
      stage.log_run!("uat_test_completed", output: output)
    end

    private

    attr_reader :workflow, :stage
  end
end
