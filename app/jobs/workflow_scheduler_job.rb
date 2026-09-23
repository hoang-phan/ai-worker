class WorkflowSchedulerJob < ApplicationJob
  queue_as :stage_execution

  def perform
    workflow = Workflow.where(status: [:implementing, :reviewing]).order(:position).first
    return unless workflow
    return if workflow.processing?

    stage = workflow.current_stage
    return unless stage

    workflow.update!(processing: true)
    begin
      StageExecutor.new(workflow, stage).call
    ensure
      workflow.update!(processing: false)
    end
  end
end
