module Stages
  # The pr_check start path: a merged PR closes the workflow; otherwise a Stages::PrCheckDecision either closes it as
  # approved, merges main and hands the agent a conflict-resolution or review-fix run, or leaves it pending. The agent
  # is never spawned here — start_ai_run is the caller's callable (StartHandler#start_ai_run). Git/Github errors propagate.
  class PrCheckRun
    def initialize(workflow:, stage:, project:, github:, git:, handoff:, prompt:, start_ai_run:)
      @workflow = workflow
      @stage = stage
      @project = project
      @github = github
      @git = git
      @handoff = handoff
      @prompt = prompt
      @start_ai_run = start_ai_run
    end

    def call
      # A merged PR is done — skip review/check inspection entirely.
      if github.merged?(workflow.github_pr_url)
        workflow.update!(status: :merged)
        return stage.log_run!("pr_merged_closed")
      end

      result = Stages::PrCheckDecision.new(
        review_decision: github.review_decision(workflow.github_pr_url, handoff.reviewers),
        local_test_failing: workflow.local_test_feedback.present?,
        checks_failing: -> { github.checks_failing?(workflow.github_pr_url) }
      ).call
      result.actions.each { |action| stage.log_run!(action) }

      case result.decision
      when :approved
        workflow.update!(status: :done)
        stage.log_run!("approved_closed")
      when :changes_requested
        if git.update_with_main!(project, workflow.branch_name) == :conflict
          start_ai_run.call(Prompts::StagePrompt::CONFLICT, action: "conflict_resolution_started")
        else
          start_ai_run.call(prompt.body)
        end
      else
        stage.log_run!("no_action_pending")
      end
    end

    private

    attr_reader :workflow, :stage, :project, :github, :git, :handoff, :prompt, :start_ai_run
  end
end
