require "open3"

module Github
  # Runs `gh` in the project's clone and translates failures into CommandError.
  # Shared by Reader and Writer so command construction and error text stay
  # identical regardless of which collaborator issues the command.
  class Runner
    def initialize(project, capture: Open3.method(:capture3))
      @project = project
      @capture = capture
    end

    # `gh api` has no `-R` flag (the repo is part of its endpoint path), so
    # callers of it pass `scope_to_repo: false`.
    def run!(command, scope_to_repo: true, repo: project.repo_full_name)
      command = [ *command, "-R", repo ] if scope_to_repo
      out, err, status = capture.call(*command, chdir: project.local_directory)
      raise CommandError, "#{command.join(' ')} failed: #{err.presence || out}" unless status.success?

      out
    end

    private

    attr_reader :project, :capture
  end
end
