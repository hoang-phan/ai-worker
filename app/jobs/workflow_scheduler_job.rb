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
    Scheduling::ActiveWorkflowRunner.new(max_capacity: self.class.max_concurrent_agents).call(run_workflow_id)
  end

  # Merged PRs are only processed when the scheduler is otherwise idle: nothing
  # implementing or running an agent (workflows merely waiting on review count
  # as idle). First `done` workflows whose PR got merged become `merged`, then
  # one `merged` workflow at a time gets its Jira ticket updated (the run is
  # polled by `run_active_workflows` on later ticks, and holds the idle check
  # shut until it finishes).
  def run_post_merge_phase
    return if Scheduling::WorkflowQueries.work_in_progress?

    confirm_merges
    workflow = Scheduling::WorkflowQueries.next_merged
    execute(workflow) if workflow
  end

  # UAT tests: a ticket that reached UAT waits out its project's delay (`uat_test_at`), then the agent tests it in a
  # browser. Unlike the post-merge phase this doesn't wait for the scheduler to be idle: a test never touches the
  # git clone and nothing else depends on it, so it only needs a free agent slot (`max_concurrent_agents`). A
  # `uat_testing` workflow that isn't running is a failed attempt being retried.
  def run_uat_phase
    slots = Scheduling::WorkflowQueries.free_agent_slots(max: self.class.max_concurrent_agents)
    return if slots <= 0

    Scheduling::WorkflowQueries.due_uat_tests(limit: slots).each do |workflow|
      workflow.update!(status: :uat_testing) if workflow.uat_waiting?
      execute(workflow)
    end
  end

  def confirm_merges
    Scheduling::WorkflowQueries.merge_candidates.each do |workflow|
      next unless workflow.tracks_jira_after_merge?

      pr_check = workflow.stages.find_by(stage_type: :pr_check)
      next unless pr_check

      Stages::MergeCheck.new(workflow: workflow, stage: pr_check, github: Github::Client.new(workflow.project)).call
    rescue StandardError => e
      Rails.logger.error("[scheduler] merge check workflow=#{workflow.id} #{e.class}: #{e.message}")
    end
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
