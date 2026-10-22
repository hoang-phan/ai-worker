module Stages
  # The failure path of a stage run. A failure stays in the current status so the next tick retries it, until
  # `threshold` consecutive failures park the workflow in `errored`, which WorkflowSchedulerJob ignores. A person
  # resumes it from the UI once the cause is fixed.
  class FailureHandler
    def initialize(workflow:, stage:, project:, error:, threshold:)
      @workflow = workflow
      @stage = stage
      @project = project
      @error = error
      @threshold = threshold
    end

    def call
      Git::BranchService.abort_merge!(project) if stage.resolving_conflicts?
      workflow.finish_ai_run!(auto_run: false)
      stage.log_run!("failed", error: error.message)
      workflow.update!(status: :errored) if stage.consecutive_failures >= threshold
    end

    private

    attr_reader :workflow, :stage, :project, :error, :threshold
  end
end
