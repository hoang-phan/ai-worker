module Workflows
  # Where an errored workflow of a ci_loop-flow project goes back to, from the newest run logged by the stages of the
  # pre-review flow (simple_implementation, ci_check, ci_verify, pr_create). nil when the workflow isn't in that part of
  # the flow, so Transitions falls back to its other rules.
  class CiLoopResume
    def initialize(workflow)
      @workflow = workflow
    end

    def status
      return nil unless @workflow.development? && @workflow.project.ci_loop_ready?

      run = StageRun.where(stage_id: @workflow.stages.select(:id)).where.not(action: "resumed").order(:id).last
      return nil unless run

      case run.stage.stage_type
      when "simple_implementation" then run.action == "ran_implementation" ? :ci_checking : :implementing
      when "ci_check" then run.action == "ci_check_completed" ? :ci_verifying : :ci_checking
      when "ci_verify" then after_verify(run.action)
      when "pr_create" then run.action == "pr_created" ? nil : :opening_pr
      end
    end

    private

    def after_verify(action)
      case action
      when "ci_verify_passed" then :opening_pr
      when "ci_verify_failed", "ci_rounds_exhausted" then :ci_checking
      else :ci_verifying
      end
    end
  end
end
