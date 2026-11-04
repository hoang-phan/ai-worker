module Stages
  class LocalTestFinish
    def initialize(workflow:, stage:, handoff:)
      @workflow = workflow
      @stage = stage
      @handoff = handoff
    end

    # The prompt makes the agent end with `LOCAL_TEST_RESULT: PASSED|FAILED|BLOCKED` once its PR comment is posted.
    # Whatever the verdict the PR goes on to review (a person sees the comment); only PASSED turns on auto-merge. A
    # FAILED round with a retest left takes the stage's failure branch (the review by default, which fixes it and
    # sends the workflow back here); otherwise the workflow just moves on.
    def call(output)
      parsed_output = AiCli::Output.new(output)
      result = parsed_output.local_test_result
      raise AiCli::CommandError, "agent finished without a LOCAL_TEST_RESULT line, treating the local test as failed" unless result

      outcome = Stages::LocalTestPolicy.outcome(result: result, completed_rounds: stage.completed_local_test_rounds)
      feedback = retest_feedback(outcome, parsed_output)
      if outcome.retest?
        workflow.stage_route_failed!(stage, local_test_feedback: feedback)
      else
        workflow.stage_complete!(stage, local_test_feedback: feedback)
      end
      stage.log_run!("local_test_completed", output: output)
      stage.log_run!("local_test_rounds_exhausted") if outcome.rounds_exhausted?
      handoff.enable_auto_merge!(workflow.github_pr_url) if outcome.auto_merge?
      handoff.notify_reviewers!
    end

    private

    attr_reader :workflow, :stage, :handoff

    def retest_feedback(outcome, parsed_output)
      return unless outcome.retest?

      Stages::LocalTestPolicy.feedback(output_block: parsed_output.local_test_feedback_block, pr_url: workflow.github_pr_url)
    end
  end
end
