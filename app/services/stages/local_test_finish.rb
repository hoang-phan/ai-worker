module Stages
  class LocalTestFinish
    def initialize(workflow:, stage:, handoff:)
      @workflow = workflow
      @stage = stage
      @handoff = handoff
    end

    # The prompt makes the agent end with `LOCAL_TEST_RESULT: PASSED|FAILED|BLOCKED` once its PR comment is posted.
    # Whatever the verdict the PR goes on to review (a person sees the comment); only PASSED turns on auto-merge.
    def call(output)
      result = AiCli::Output.new(output).local_test_result
      raise AiCli::CommandError, "agent finished without a LOCAL_TEST_RESULT line, treating the local test as failed" unless result

      outcome = Stages::LocalTestPolicy.outcome(result: result, completed_rounds: stage.completed_local_test_rounds)
      feedback = AiCli::Output.new(output).local_test_feedback_block
      workflow.update!(Workflow::AI_RUN_RESET.merge(
        status: :reviewing,
        local_test_feedback: outcome.retest? ? Stages::LocalTestPolicy.feedback(output_block: feedback, pr_url: workflow.github_pr_url) : nil
      ))
      stage.log_run!("local_test_completed", output: output)
      stage.log_run!("local_test_rounds_exhausted") if outcome.rounds_exhausted?
      handoff.enable_auto_merge!(workflow.github_pr_url) if outcome.auto_merge?
      handoff.notify_reviewers!
    end

    private

    attr_reader :workflow, :stage, :handoff
  end
end
