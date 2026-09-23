class WorkflowSchedulerJob < ApplicationJob
  queue_as :stage_execution

  def perform
    workflow = Workflow.active.order(:position).first
    return unless workflow
    return if workflow.processing?

    stage = workflow.next_stage
    return unless stage

    workflow.update!(processing: true)
    begin
      StageExecutor.new(workflow, stage).call
    ensure
      workflow.update!(processing: false)
    end
  end
end
