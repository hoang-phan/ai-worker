module Stages
  # The success path of jira_update: the agent moved the ticket, and we maybe schedule a UAT test. The
  # AiCli::CommandError raised here for a missing result marker propagates to StageExecutor's rescue.
  class JiraUpdateFinish
    def initialize(workflow:, stage:, project:, clock: -> { Time.current })
      @workflow = workflow
      @stage = stage
      @project = project
      @clock = clock
    end

    # The prompt makes the agent end with `JIRA_RESULT: UAT` or
    # `JIRA_RESULT: RELEASEABLE`; without it we can't tell the ticket moved.
    def call(output)
      outcome = AiCli::Output.new(output).jira_result
      raise AiCli::CommandError, "agent finished without a JIRA_RESULT line, treating the Jira update as failed" unless outcome

      # A ticket that went to UAT is tested by the agent after the project's delay, if the project opted in.
      if outcome.casecmp?("UAT") && project.uat_test_ready?
        run_at = clock.call + project.uat_test_delay_minutes.minutes
        workflow.finish_ai_run!(status: :uat_waiting, uat_test_at: run_at)
        stage.log_run!("jira_updated", output: output)
        stage.log_run!("uat_test_scheduled", output: "UAT test scheduled for #{run_at.iso8601}")
      else
        workflow.finish_ai_run!(status: :jira_updated)
        stage.log_run!("jira_updated", output: output)
      end
    end

    private

    attr_reader :workflow, :stage, :project, :clock
  end
end
