module Stages
  # The failure path of a stage run. A failure stays in the current status so the next tick retries it, until
  # `threshold` consecutive failures park the workflow in `errored`, which WorkflowSchedulerJob ignores. A person
  # resumes it from the UI once the cause is fixed. A runbook workflow only starts on a tick while `auto_run` is set,
  # so it keeps `auto_run` through a retryable failure (otherwise the first failure would strand it).
  class FailureHandler
    def initialize(workflow:, stage:, project:, error:, threshold:, git: Git::BranchService)
      @workflow = workflow
      @stage = stage
      @project = project
      @error = error
      @threshold = threshold
      @git = git
    end

    def call
      git.abort_merge!(project) if stage.resolving_conflicts?
      stage.log_run!("failed", error: error.message)
      exhausted = stage.consecutive_failures >= threshold
      workflow.finish_ai_run!(auto_run: workflow.runbook? && !exhausted, **(exhausted ? { status: :errored } : {}))
    end

    private

    attr_reader :workflow, :stage, :project, :error, :threshold, :git
  end
end
