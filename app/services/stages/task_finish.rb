module Stages
  # The success path of a task stage: mark the workflow done, then push best effort.
  class TaskFinish
    def initialize(workflow:, stage:, project:, git:)
      @workflow = workflow
      @stage = stage
      @project = project
      @git = git
    end

    def call(output)
      workflow.finish_ai_run!(status: :done)
      stage.log_run!("task_completed", output: output)
      push_task_commits
    end

    private

    attr_reader :workflow, :stage, :project, :git

    # The task prompt may or may not tell the agent to push, so do it here. Best effort and after the workflow is
    # `done`: a failed push is logged, never fails the stage (a retry would re-run the whole task).
    def push_task_commits
      stage.log_run!("task_pushed") if git.push_current!(project) == :pushed
    rescue Git::CommandError => e
      stage.log_run!("task_push_failed", error: e.message)
    end
  end
end
