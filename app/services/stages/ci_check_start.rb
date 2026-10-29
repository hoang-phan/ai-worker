module Stages
  # Plain code, no agent: the stage's own command, else the project's. The launcher the executor hands over runs the project's CI command detached, in the clone
  # (put back on this workflow's own branch first: the clone is shared, and CI signs off whatever HEAD is), with the output in a log the verify stage reads.
  # Reviews of other people's PRs never run CI.
  class CiCheckStart
    def initialize(workflow:, stage:, project:, git:, launcher:)
      @workflow = workflow
      @stage = stage
      @project = project
      @git = git
      @launcher = launcher
    end

    def call
      command = stage.command.presence || project.ci_command
      raise ArgumentError, "project #{project.name} has no CI command for the check stage" if command.blank?

      raise ArgumentError, "workflow #{workflow.id} is a PR review; it never runs CI" if workflow.pr_review?

      git.ensure_on_branch!(project, workflow.branch_name)
      launcher.call(command)
    end

    private

    attr_reader :workflow, :stage, :project, :git, :launcher
  end
end
