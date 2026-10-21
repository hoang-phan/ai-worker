module Stages
  # The success path of a finished agent run: per stage type, the Workflow/StageRun mutations and the best-effort
  # follow-ups (auto-merge, reviewer notification, task push). StageExecutor still owns polling, logging setup and
  # error rescue; the AiCli::CommandErrors raised here for missing result markers propagate to its rescue.
  class CompletionHandler
    def initialize(workflow:, stage:, project:, github:, git:, handoff:)
      @workflow = workflow
      @stage = stage
      @project = project
      @github = github
      @git = git
      @handoff = handoff
    end

    def call(output)
      case stage.stage_type
      when "implementation" then Stages::ImplementationFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call(output)
      when "pr_check" then Stages::PrCheckFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call(output)
      when "task" then finish_task(output)
      when "pr_review" then finish_pr_review(output)
      when "jira_update" then Stages::JiraLifecycleFinish.new(workflow: workflow, stage: stage, project: project).call(output)
      when "uat_test" then Stages::JiraLifecycleFinish.new(workflow: workflow, stage: stage, project: project).call(output)
      when "local_test" then Stages::LocalTestFinish.new(workflow: workflow, stage: stage, handoff: handoff).call(output)
      when "runbook_step" then Stages::RunbookStepFinish.new(workflow: workflow, stage: stage).call(output)
      end
    end

    private

    attr_reader :workflow, :stage, :project, :github, :git, :handoff

    def finish_task(output)
      workflow.update!(Workflow::AI_RUN_RESET.merge(status: :done))
      stage.log_run!("task_completed", output: output)
      push_task_commits
    end

    def finish_pr_review(output)
      workflow.update!(Workflow::AI_RUN_RESET.merge(status: :done))
      stage.log_run!("review_completed", output: output)
    end

    # The task prompt may or may not tell the agent to push, so do it here. Best effort and after the workflow is
    # `done`: a failed push is logged, never fails the stage (a retry would re-run the whole task).
    def push_task_commits
      stage.log_run!("task_pushed") if git.push_current!(project) == :pushed
    rescue Git::CommandError => e
      stage.log_run!("task_push_failed", error: e.message)
    end
  end
end
