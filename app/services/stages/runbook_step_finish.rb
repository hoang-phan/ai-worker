module Stages
  # The success path of a runbook step. A message step must confirm its Slack
  # post, while either kind can pass output variables to later steps.
  class RunbookStepFinish
    def initialize(workflow:, stage:, enqueue: ->(workflow_id) { WorkflowSchedulerJob.perform_later(workflow_id) })
      @workflow = workflow
      @stage = stage
      @enqueue = enqueue
    end

    def call(output)
      result = AiCli::Output.new(output)
      if stage.run_message? && !result.posted?
        raise AiCli::CommandError, "agent finished without confirming the Slack message was posted (no POSTED line)"
      end

      workflow.update!(Workflow::AI_RUN_RESET.merge(
        status: :waiting,
        awaiting_next: true,
        variables: workflow.variables.merge(result.variables)
      ))
      stage.log_run!("stage_completed", output: output)
      stage.log_run!("message_sent") if stage.run_message?
      return unless stage.auto_advance?

      workflow.advance!
      enqueue.call(workflow.id) if workflow.auto_run?
    end

    private

    attr_reader :workflow, :stage, :enqueue
  end
end
