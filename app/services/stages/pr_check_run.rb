module Stages
  # The pr_check start path: a merged PR closes the workflow; otherwise a Stages::PrCheckDecision either closes it as
  # approved, merges main and hands the agent a conflict-resolution or review-fix run, or leaves it pending. The agent
  # is never spawned here — launcher is the caller's callable (Stages::AiRunLauncher). Git/Github errors propagate.
  class PrCheckRun
    def initialize(workflow:, stage:, project:, github:, git:, handoff:, prompt:, launcher:)
      @workflow = workflow
      @stage = stage
      @project = project
      @github = github
      @git = git
      @handoff = handoff
      @prompt = prompt
      @launcher = launcher
    end

    def call
      # A merged PR is done — skip review/check inspection entirely.
      return close_merged if github.merged?(workflow.github_pr_url)

      result = decision
      result.actions.each { |action| stage.log_run!(action) }

      case result.decision
      when :approved then close_approved
      when :changes_requested then start_fix_run
      else stage.log_run!("no_action_pending")
      end
    end

    private

    def close_merged
      workflow.update!(status: :merged)
      stage.log_run!("pr_merged_closed")
    end

    def decision
      Stages::PrCheckDecision.new(
        review_decision: github.review_decision(workflow.github_pr_url, handoff.reviewers),
        local_test_failing: workflow.local_test_feedback.present?,
        checks_failing: -> { github.checks_failing?(workflow.github_pr_url) }
      ).call
    end

    def close_approved
      workflow.update!(status: :done)
      stage.log_run!("approved_closed")
    end

    def start_fix_run
      if git.update_with_main!(project, workflow.branch_name) == :conflict
        launcher.call(Prompts::StagePrompt::CONFLICT, action: "conflict_resolution_started")
      else
        launcher.call(prompt.body)
      end
    end

    attr_reader :workflow, :stage, :project, :github, :git, :handoff, :prompt, :launcher
  end
end
