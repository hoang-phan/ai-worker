class StageExecutor
  # How long a background the agent CLI run is allowed to sit without
  # finishing before we give up on it and mark the stage failed. Guards
  # against a hung/orphaned process blocking this workflow forever.
  STALE_AFTER = 3.hours

  # After this many consecutive `failed` runs for a stage the workflow is
  # parked as `errored` (each retry is a full agent CLI run), so the scheduler
  # moves on to the next workflow until someone resumes it — see docs/RUNBOOK.md.
  MAX_CONSECUTIVE_FAILURES = 3

  # `github:`, `git:`, `tooling:`, `ai_run_poll:` and `handoff:` default to production collaborators, as do the
  # `*_class:` factories for the start/completion/conflict-finish handlers and the launcher; specs pass doubles.
  def initialize(workflow, stage, github: nil, git: Git::BranchService, tooling: nil, ai_run_poll: nil, handoff: nil,
                 start_handler_class: Stages::StartHandler, completion_handler_class: Stages::CompletionHandler,
                 conflict_resolution_finish_class: Stages::ConflictResolutionFinish,
                 launcher_class: Stages::AiRunLauncher)
    @workflow = workflow
    @stage = stage
    @project = workflow.project
    @github = github
    @git = git
    @tooling = tooling || Stages::RunTooling.for(stage)
    @ai_run_poll = ai_run_poll || Stages::AiRunPoll.new(
      workflow: workflow, stage: stage, poller_class: @tooling.poller_class, stale_after: STALE_AFTER
    )
    @handoff = handoff
    @start_handler_class = start_handler_class
    @completion_handler_class = completion_handler_class
    @conflict_resolution_finish_class = conflict_resolution_finish_class
    @launcher_class = launcher_class
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

  private

  attr_reader :workflow, :stage, :project, :git, :tooling, :ai_run_poll,
              :start_handler_class, :completion_handler_class, :conflict_resolution_finish_class, :launcher_class

  def github
    @github ||= Github::Client.new(project)
  end

  def start_handler
    @start_handler ||= start_handler_class.new(
      workflow: workflow, stage: stage, project: project,
      github: github, git: git, prompt: prompt, handoff: handoff, launcher: launcher
    )
  end

  def poll_ai_run
    output = ai_run_poll.call
    finalize_success(output) if output
  end

  def finalize_success(output)
    return conflict_resolution_finish.call(output) if stage.resolving_conflicts?

    completion_handler_class.new(
      workflow: workflow, stage: stage, project: project,
      github: github, git: git, handoff: handoff
    ).call(output)
  end

  def conflict_resolution_finish
    conflict_resolution_finish_class.new(
      workflow: workflow, stage: stage, project: project,
      git: git, prompt: prompt, launcher: launcher
    )
  end

  def fail_stage(error)
    Stages::FailureHandler.new(
      workflow: workflow, stage: stage, project: project, error: error, threshold: MAX_CONSECUTIVE_FAILURES, git: git
    ).call
  end

  def handoff
    @handoff ||= Stages::ReviewHandoff.new(workflow, stage, github: github)
  end

  def prompt
    @prompt ||= Prompts::StagePrompt.new(workflow, stage)
  end

  def launcher
    @launcher ||= launcher_class.new(
      workflow: workflow, stage: stage, project: project, runner: tooling.runner
    )
  end
end
