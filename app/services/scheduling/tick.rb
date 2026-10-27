module Scheduling
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
  class Tick
    def initialize(max_capacity:, active_runner: nil, post_merge_phase: nil, uat_phase: nil)
      @max_capacity = max_capacity
      @active_runner = active_runner
      @post_merge_phase = post_merge_phase
      @uat_phase = uat_phase
    end

    def call(run_workflow_id = nil)
      active_runner.call(run_workflow_id)
      post_merge_phase.call
      uat_phase.call
    end

    private

    def active_runner
      @active_runner ||= ActiveWorkflowRunner.new(max_capacity: @max_capacity)
    end

    def post_merge_phase
      @post_merge_phase ||= PostMergePhase.new
    end

    def uat_phase
      @uat_phase ||= UatPhase.new(max_capacity: @max_capacity)
    end
  end
end
