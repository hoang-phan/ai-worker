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
      when "jira_update" then finish_jira_update(output)
      when "uat_test" then finish_uat_test(output)
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

    # The prompt makes the agent end with `JIRA_RESULT: UAT` or
    # `JIRA_RESULT: RELEASEABLE`; without it we can't tell the ticket moved.
    def finish_jira_update(output)
      outcome = AiCli::Output.new(output).jira_result
      raise AiCli::CommandError, "agent finished without a JIRA_RESULT line, treating the Jira update as failed" unless outcome

      # A ticket that went to UAT is tested by the agent after the project's delay, if the project opted in.
      if outcome.casecmp?("UAT") && project.uat_test_ready?
        run_at = project.uat_test_delay_minutes.minutes.from_now
        workflow.update!(Workflow::AI_RUN_RESET.merge(status: :uat_waiting, uat_test_at: run_at))
        stage.log_run!("jira_updated", output: output)
        stage.log_run!("uat_test_scheduled", output: "UAT test scheduled for #{run_at.iso8601}")
      else
        workflow.update!(Workflow::AI_RUN_RESET.merge(status: :jira_updated))
        stage.log_run!("jira_updated", output: output)
      end
    end

    # The prompt makes the agent end with `UAT_RESULT: PASSED|FAILED|BLOCKED` once its comment is on the ticket. Any of
    # the three is a finished test (the verdict lives in the comment and this log); no line means we can't tell the
    # comment was posted, so the stage fails and retries like any other.
    def finish_uat_test(output)
      result = AiCli::Output.new(output).uat_result
      raise AiCli::CommandError, "agent finished without a UAT_RESULT line, treating the UAT test as failed" unless result

      workflow.update!(Workflow::AI_RUN_RESET.merge(status: :uat_tested))
      stage.log_run!("uat_test_completed", output: output)
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
