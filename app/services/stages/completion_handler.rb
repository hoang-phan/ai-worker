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
      when "implementation" then finish_implementation(output)
      when "pr_check" then Stages::PrCheckFinish.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call(output)
      when "task" then finish_task(output)
      when "pr_review" then finish_pr_review(output)
      when "jira_update" then finish_jira_update(output)
      when "uat_test" then finish_uat_test(output)
      when "local_test" then Stages::LocalTestFinish.new(workflow: workflow, stage: stage, handoff: handoff).call(output)
      when "runbook_step" then finish_runbook_step(output)
      end
    end

    private

    attr_reader :workflow, :stage, :project, :github, :git, :handoff

    def finish_implementation(output)
      pr_url = github.find_pr_url(branch_name: workflow.branch_name, jira_ticket: workflow.jira_ticket, output: output)
      testing_locally = workflow.development? && project.local_test_ready?
      workflow.update!(Workflow::AI_RUN_RESET.merge(github_pr_url: pr_url, status: testing_locally ? :local_testing : :reviewing))
      stage.log_run!("ran_implementation", output: output)
      # Auto-merge waits until the local test passed, so a PR can't merge while it is still being tested.
      handoff.enable_auto_merge!(pr_url) unless testing_locally
      handoff.notify_reviewers! unless testing_locally
    end

    def finish_task(output)
      workflow.update!(Workflow::AI_RUN_RESET.merge(status: :done))
      stage.log_run!("task_completed", output: output)
      push_task_commits
    end

    def finish_pr_review(output)
      workflow.update!(Workflow::AI_RUN_RESET.merge(status: :done))
      stage.log_run!("review_completed", output: output)
    end

    # The workflow parks in `waiting` until someone clicks Next (Workflow#advance!), unless the stage is
    # `auto_advance`: then it moves straight on and the scheduler starts the next stage. Agents can hand values to later stages with lines like
    # `VAR: VERSION=2.21.1-f839742`, which become workflow variables / {VERSION}.
    def finish_runbook_step(output)
      if stage.run_message? && !AiCli::Output.new(output).posted?
        raise AiCli::CommandError, "agent finished without confirming the Slack message was posted (no POSTED line)"
      end

      workflow.update!(Workflow::AI_RUN_RESET.merge(status: :waiting, awaiting_next: true,
                                           variables: workflow.variables.merge(AiCli::Output.new(output).variables)))
      stage.log_run!("stage_completed", output: output)
      stage.log_run!("message_sent") if stage.run_message?
      return unless stage.auto_advance?

      workflow.advance!
      WorkflowSchedulerJob.perform_later(workflow.id) if workflow.auto_run?
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
