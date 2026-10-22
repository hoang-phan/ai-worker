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
      retest = Stages::LocalTestPolicy.retest_after_fix?(
        local_test_ready: project.local_test_ready?,
        completed_rounds: workflow.stages.find_by(stage_type: :local_test)&.completed_local_test_rounds.to_i,
        feedback_pending: workflow.local_test_feedback.present?,
        retest_requested: parsed_output.retest_requested?
      )
      workflow.finish_ai_run!(local_test_feedback: nil, **(retest ? { status: :local_testing } : {}))
      stage.log_run!("requested_changes_fixed", output: output)
      stage.log_run!("local_test_retest_scheduled") if retest
      handoff.notify_reviewers!(again: true, fixed: parsed_output.fixed_summary) unless retest
    end

    private

    attr_reader :workflow, :stage, :project, :github, :handoff
  end
end
