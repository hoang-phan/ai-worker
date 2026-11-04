module Stages
  # The success path of a pr_check review-fix run: request another review, then
  # either return to local testing or notify reviewers with the agent's summary.
  class PrCheckFinish
    def initialize(workflow:, stage:, project:, github:, handoff:)
      @workflow = workflow
      @stage = stage
      @project = project
      @github = github
      @handoff = handoff
    end

    def call(output)
      parsed_output = AiCli::Output.new(output)
      github.request_review!(workflow.github_pr_url, handoff.reviewers)
      retest = retest?(parsed_output)
      # The fix is in: ask for another look (back to this stage by default, its failure target) or retest it locally first.
      target = if retest then workflow.stage_enter!(local_test_stage, local_test_feedback: nil)
      else workflow.stage_route_failed!(stage, local_test_feedback: nil)
      end
      stage.log_run!("requested_changes_fixed", output: output)
      record_lessons(parsed_output.lessons)
      stage.log_run!("local_test_retest_scheduled") if retest
      handoff.notify_reviewers!(again: true, fixed: parsed_output.fixed_summary) if target && !retest
    end

    private

    attr_reader :workflow, :stage, :project, :github, :handoff

    # Best effort: a lesson that cannot be saved never fails the stage.
    def record_lessons(new_lessons)
      project.add_agent_lessons(new_lessons)
    rescue StandardError => e
      Rails.logger.warn("Could not save agent lessons for project #{project.id}: #{e.message}")
    end

    def retest?(parsed_output)
      Stages::LocalTestPolicy.retest_after_fix?(
        local_test_ready: workflow.local_test_stage?,
        completed_rounds: completed_local_test_rounds,
        feedback_pending: workflow.local_test_feedback.present?,
        retest_requested: parsed_output.retest_requested?
      )
    end

    def completed_local_test_rounds
      local_test_stage&.completed_local_test_rounds.to_i
    end

    def local_test_stage
      workflow.stages.find_by(stage_type: :local_test)
    end
  end
end
