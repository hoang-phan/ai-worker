class StageExecutor
  # How long a background the agent CLI run is allowed to sit without
  # finishing before we give up on it and mark the stage failed. Guards
  # against a hung/orphaned process blocking this workflow forever.
  STALE_AFTER = 3.hours

  # After this many consecutive `failed` runs for a stage the workflow is
  # parked as `errored` (each retry is a full agent CLI run), so the scheduler
  # moves on to the next workflow until someone resumes it — see docs/RUNBOOK.md.
  MAX_CONSECUTIVE_FAILURES = 3

  def initialize(workflow, stage)
    @workflow = workflow
    @stage = stage
    @project = workflow.project
  end

  def call
    raise ArgumentError, "project #{project.name} points at the live ai-worker checkout; use a separate clone" if project.runs_from_live_checkout?

    if workflow.processing?
      poll_ai_run
    else
      start_handler.call
    end
  rescue Git::CommandError, Github::CommandError, AiCli::CommandError, ArgumentError => e
    fail_stage(e)
  end

  # A `done` workflow whose PR has since been merged becomes `merged`. Called
  # by the scheduler only on idle ticks. A failed lookup is logged and retried
  # next idle tick — it never fails the workflow.
  def check_merged
    return unless Github::Client.new(project).merged?(workflow.github_pr_url)

    workflow.update!(status: :merged)
    log(action: "pr_merged_detected")
  rescue Github::CommandError => e
    log(action: "merge_check_failed", error: e.message)
  end

  private

  attr_reader :workflow, :stage, :project

  def start_handler
    @start_handler ||= Stages::StartHandler.new(
      workflow: workflow, stage: stage, project: project,
      github: Github::Client.new(project), git: Git::BranchService, prompt: prompt, handoff: handoff
    )
  end

  def poll_ai_run
    poller = AiCli::RunPoller.new(
      pid: workflow.ai_pid, log_path: workflow.ai_log_path, log_offset: workflow.ai_log_offset,
      started_at: workflow.ai_started_at, log_tag: log_tag, stale_after: STALE_AFTER
    )
    begin
      state, output = poller.call
    ensure
      workflow.update_column(:ai_log_offset, poller.log_offset) if poller.log_offset != workflow.ai_log_offset
    end
    return if state == :running

    finalize_success(output)
  end

  def finalize_success(output)
    return finish_conflict_resolution(output) if stage.resolving_conflicts?

    Stages::CompletionHandler.new(
      workflow: workflow, stage: stage, project: project,
      github: Github::Client.new(project), git: Git::BranchService, handoff: handoff
    ).call(output)
  end

  # The conflict-resolution run must leave the merge committed; only then does
  # the review-fix prompt run (immediately, in the same tick).
  def finish_conflict_resolution(output)
    if Git::BranchService.merge_in_progress?(project)
      Git::BranchService.abort_merge!(project)
      raise AiCli::CommandError, "#{AiCli::Runner.agent} did not finish resolving merge conflicts with main"
    end

    workflow.update!(Workflow::AI_RUN_RESET)
    log(action: "conflicts_resolved", output: output)
    start_handler.start_ai_run(prompt.body)
  end

  def fail_stage(error)
    Stages::FailureHandler.new(
      workflow: workflow, stage: stage, project: project, error: error, threshold: MAX_CONSECUTIVE_FAILURES
    ).call
  end

  def log_tag
    "workflow=#{workflow.id} stage=#{stage.id}"
  end

  def handoff
    @handoff ||= Stages::ReviewHandoff.new(workflow, stage)
  end

  def prompt
    @prompt ||= Prompts::StagePrompt.new(workflow, stage)
  end

  def log(action:, output: nil, error: nil)
    stage.stage_runs.create!(action: action, output: output, error: error)
  end
end
