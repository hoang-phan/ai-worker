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
  def perform
    workflows = Workflow.where(status: [ :implementing, :reviewing ]).includes(:project).order(:position).to_a
    return if workflows.empty?

    running, waiting = workflows.partition(&:processing?)
    # An earlier (lower position) workflow that's merely waiting on review still
    # holds its project's slot, even if a later one is the one in flight.
    # Workflows on one project run strictly one after another: only the first
    # (by position) is eligible to start; later ones wait until it is done.
    heads = workflows.uniq { |workflow| clone_key(workflow.project) }
    waiting &= heads

    # Poll in-flight runs first so finished ones free their slot/clone this tick.
    running.each { |workflow| execute(workflow) }

    busy_dirs = Workflow.where(processing: true).includes(:project).map { |w| clone_key(w.project) }
    active = busy_dirs.size

    waiting.each do |workflow|
      next if active >= self.class.max_concurrent_agents
      next if busy_dirs.include?(clone_key(workflow.project))

      execute(workflow)
      next unless workflow.reload.processing?

      busy_dirs << clone_key(workflow.project)
      active += 1
    end
  end

  private

  # Projects pointing at the same clone via different spellings ("~/x", "x/",
  # symlinks) must still count as one clone, or the per-clone guard misses them.
  def clone_key(project)
    path = File.expand_path(project.local_directory.to_s)
    File.exist?(path) ? File.realpath(path) : path
  end

  # One workflow's failure must not stop the rest of the tick.
  def execute(workflow)
    stage = workflow.current_stage
    return unless stage

    StageExecutor.new(workflow, stage).call
  rescue StandardError => e
    Rails.logger.error("[scheduler] workflow=#{workflow.id} #{e.class}: #{e.message}")
  end
end
