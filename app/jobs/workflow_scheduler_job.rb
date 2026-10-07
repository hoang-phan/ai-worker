class WorkflowSchedulerJob < ApplicationJob
  queue_as :stage_execution

  # Always returns quickly: StageExecutor never blocks on the agent CLI (`claude -p` / `agent -p`)
  # itself (it starts the run in the background and returns, or polls a
  # previously-started run without waiting on it) — see
  # docs/RUNBOOK.md for why the job can no longer block here.
  def perform
    workflow = Workflow.where(status: [ :implementing, :reviewing ]).order(:position).first
    return unless workflow

    stage = workflow.current_stage
    return unless stage

    StageExecutor.new(workflow, stage).call
  end
end
