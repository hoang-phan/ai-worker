module Stages
  # The success path of the Jira-facing stages: jira_update (moved the ticket, maybe schedules a UAT test) and
  # uat_test (commented the verdict on the ticket). The AiCli::CommandErrors raised here for missing result markers
  # propagate to StageExecutor's rescue.
  class JiraLifecycleFinish
    def initialize(workflow:, stage:, project:)
      @workflow = workflow
      @stage = stage
      @project = project
    end

    def call(output)
      case stage.stage_type
      when "jira_update" then finish_jira_update(output)
      when "uat_test" then finish_uat_test(output)
      end
    end

    private

    attr_reader :workflow, :stage, :project

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
  end
end
