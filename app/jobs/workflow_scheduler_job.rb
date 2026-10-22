class WorkflowSchedulerJob < ApplicationJob
  queue_as :stage_execution

  # Max agent CLI runs (`claude -p` / `agent -p`) in flight at once, across all projects.
  def self.max_concurrent_agents
    ENV.fetch("MAX_CONCURRENT_AGENTS", 3).to_i
  end

  # Always returns quickly: StageExecutor never blocks on the agent CLI itself
  # (it starts the run in the background and returns, or polls a
  # previously-started run without waiting on it) — see docs/RUNBOOK.md.
  #
  # Each tick walks every in-flight workflow (in `position` order) so one stuck
  # in review never starves the others. Two rules keep concurrent runs safe:
  #   * one running agent per local clone — stages `git checkout`/`pull`/`merge`
  #     in `project.local_directory`, which would corrupt a run in progress;
  #   * at most `max_concurrent_agents` runs overall.
  # Keep the scheduler queue at concurrency 1: ticks must stay serialized, since
  # the checks above aren't atomic.
  #
  # `run_workflow_id` is the manual trigger (a runbook's "Run stage" button). Runbook
  # workflows are started by the cron tick only while `auto_run` is set (by Run / Next, kept
  # through stages with `auto_advance`, cleared at a pause or failure); otherwise only by being named here.
  def perform(run_workflow_id = nil)
    Scheduling::ActiveWorkflowRunner.new(max_capacity: self.class.max_concurrent_agents).call(run_workflow_id)
    Scheduling::PostMergePhase.new.call
    Scheduling::UatPhase.new(max_capacity: self.class.max_concurrent_agents).call
  end
end
