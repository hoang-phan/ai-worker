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
    run_active_workflows(run_workflow_id)
    run_post_merge_phase
    run_uat_phase
  end

  private

  def run_active_workflows(run_workflow_id = nil)
    active_workflows = Workflow.where(status: [ :implementing, :reviewing, :local_testing ]).includes(:project).order(:position).to_a
    # A Jira update (`merged`) or a UAT test (`uat_testing`) that's mid-run is polled like any other run.
    updating = Workflow.where(status: [ :merged, :uat_testing ], processing: true).includes(:project).order(:position).to_a
    workflows = active_workflows + updating
    return if workflows.empty?

    running, waiting = workflows.partition(&:processing?)
    # An earlier (lower position) workflow that's merely waiting on review still
    # holds its project's slot, even if a later one is the one in flight.
    # Workflows on one project run strictly one after another: only the first
    # (by position) is eligible to start; later ones wait until it is done.
    # Runbook workflows are exempt like PR reviews, and start on a cron tick only when `auto_run`
    # is set; otherwise a person starts the stage with "Run stage" (`run_workflow_id`). Once it runs
    # it is polled like any other run, then moves on (`auto_advance`) or parks in `waiting` until Next.
    # PR-review workflows are the exception: they run once and never wait on
    # anyone, so they neither hold the slot nor are blocked by a development
    # workflow that is only waiting on its PR — only a *running* agent on the
    # same clone (the busy_dirs check below) holds them back.
    heads = active_workflows.select(&:development?).uniq { |workflow| clone_key(workflow.project) }
    waiting = waiting.select do |workflow|
      if workflow.runbook? then workflow.id == run_workflow_id || workflow.auto_run?
      else workflow.pr_review? || heads.include?(workflow)
      end
    end

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

  # Merged PRs are only processed when the scheduler is otherwise idle: nothing
  # implementing or running an agent (workflows merely waiting on review count
  # as idle). First `done` workflows whose PR got merged become `merged`, then
  # one `merged` workflow at a time gets its Jira ticket updated (the run is
  # polled by `run_active_workflows` on later ticks, and holds the idle check
  # shut until it finishes).
  def run_post_merge_phase
    return if work_in_progress?

    confirm_merges
    workflow = Workflow.merged.where(processing: false).includes(:project).order(:position).first
    execute(workflow) if workflow
  end

  # UAT tests: a ticket that reached UAT waits out its project's delay (`uat_test_at`), then the agent tests it in a
  # browser. Unlike the post-merge phase this doesn't wait for the scheduler to be idle: a test never touches the
  # git clone and nothing else depends on it, so it only needs a free agent slot (`max_concurrent_agents`). A
  # `uat_testing` workflow that isn't running is a failed attempt being retried.
  def run_uat_phase
    slots = self.class.max_concurrent_agents - Workflow.where(processing: true).count
    return if slots <= 0

    due = Workflow.where(status: :uat_waiting).where(uat_test_at: ..Time.current)
                  .or(Workflow.where(status: :uat_testing, processing: false))
    due.includes(:project).order(:uat_test_at).limit(slots).each do |workflow|
      workflow.update!(status: :uat_testing) if workflow.uat_waiting?
      execute(workflow)
    end
  end

  def work_in_progress?
    Workflow.where(status: [ :implementing, :local_testing ]).exists? || Workflow.where(processing: true).exists?
  end

  def confirm_merges
    Workflow.done.development.where.not(github_pr_url: nil).includes(:project).order(:position).each do |workflow|
      next unless workflow.tracks_jira_after_merge?

      pr_check = workflow.stages.find_by(stage_type: :pr_check)
      StageExecutor.new(workflow, pr_check).check_merged if pr_check
    rescue StandardError => e
      Rails.logger.error("[scheduler] merge check workflow=#{workflow.id} #{e.class}: #{e.message}")
    end
  end

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
