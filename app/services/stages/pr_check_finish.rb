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
      workflow.finish_ai_run!(local_test_feedback: nil, **(retest ? { status: :local_testing } : {}))
      stage.log_run!("requested_changes_fixed", output: output)
      record_lessons(parsed_output.lessons)
      stage.log_run!("local_test_retest_scheduled") if retest
      handoff.notify_reviewers!(again: true, fixed: parsed_output.fixed_summary) unless retest
    end

    private

    MAX_LESSONS = 40

    attr_reader :workflow, :stage, :project, :github, :handoff

    # Best effort: a lesson that cannot be saved never fails the stage.
    def record_lessons(new_lessons)
      return if new_lessons.empty?

      lines = project.agent_lessons.to_s.lines.map(&:strip).reject(&:blank?)
      new_lessons.each { |lesson| lines << lesson unless lines.any? { |line| line.casecmp?(lesson) } }
      project.update_column(:agent_lessons, lines.last(MAX_LESSONS).join("\n"))
    rescue StandardError => e
      Rails.logger.warn("Could not save agent lessons for project #{project.id}: #{e.message}")
    end

    def retest?(parsed_output)
      Stages::LocalTestPolicy.retest_after_fix?(
        local_test_ready: project.local_test_ready?,
        completed_rounds: completed_local_test_rounds,
        feedback_pending: workflow.local_test_feedback.present?,
        retest_requested: parsed_output.retest_requested?
      )
    end

    def completed_local_test_rounds
      workflow.stages.find_by(stage_type: :local_test)&.completed_local_test_rounds.to_i
    end
  end
end
