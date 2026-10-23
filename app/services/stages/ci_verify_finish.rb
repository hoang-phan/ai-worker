module Stages
  # The success path of a verify run. The prompt makes the agent end with `CI_VERDICT: PASSED|FAILED`, having fixed what
  # the check reported when it failed (without running the whole gate) and pushed any commit it made, so the next check
  # posts its result for the new HEAD. PASSED ends the loop: the PR is already open, so the workflow goes on to local
  # testing or review. FAILED goes back to the check, at most `project.ci_max_rounds` checks, then the workflow parks as errored until a
  # person resumes it.
  class CiVerifyFinish
    def initialize(workflow:, stage:, project:, handoff:)
      @workflow = workflow
      @stage = stage
      @project = project
      @handoff = handoff
    end

    def call(output)
      verdict = AiCli::Output.new(output).ci_verdict
      raise AiCli::CommandError, "agent finished without a CI_VERDICT line, treating the verification as failed" unless verdict

      verdict == "PASSED" ? passed(output) : failed(output)
    end

    private

    attr_reader :workflow, :stage, :project, :handoff

    def passed(output)
      testing_locally = workflow.local_test_before_review?
      workflow.finish_ai_run!(status: workflow.post_pr_status)
      stage.log_run!("ci_verify_passed", output: output)
      handoff.notify_reviewers! unless testing_locally
    end

    def failed(output)
      exhausted = ci_check_stage.completed_ci_rounds >= project.ci_max_rounds
      workflow.finish_ai_run!(status: exhausted ? :errored : :ci_checking)
      stage.log_run!("ci_verify_failed", output: output)
      stage.log_run!("ci_rounds_exhausted") if exhausted
    end

    def ci_check_stage
      workflow.stages.find_or_create_by!(stage_type: :ci_check)
    end
  end
end
