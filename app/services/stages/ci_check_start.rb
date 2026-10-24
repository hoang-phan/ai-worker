module Stages
  # Plain code, no agent: the stage's own command, else the project's. The launcher the executor hands over runs the project's CI command detached, in the clone
  # (still on the branch the implementation committed to), with the output in a log the verify stage reads.
  class CiCheckStart
    def initialize(stage:, project:, launcher:)
      @stage = stage
      @project = project
      @launcher = launcher
    end

    def call
      command = stage.command.presence || project.ci_command
      raise ArgumentError, "project #{project.name} has no CI command for the check stage" if command.blank?

      launcher.call(command)
    end

    private

    attr_reader :stage, :project, :launcher
  end
end
