require "open3"

module Git
  class CommandError < StandardError; end

  # Creates (or resumes) a workflow's branch from `main` inside a project's
  # local checkout. Never shells out with a compound `cd X && ...` string —
  # always passes `chdir:` so this works the same whether the process's own
  # cwd is the orchestrator app or anything else.
  class BranchService
    def self.create_branch!(project, branch_name)
      new(project, branch_name).create!
    end

    def initialize(project, branch_name)
      @project = project
      @branch_name = branch_name
    end

    def create!
      run!(%w[git fetch origin main])

      if branch_exists_locally?
        run!([ "git", "checkout", branch_name ])
      else
        run!([ "git", "checkout", "-b", branch_name, "origin/main" ])
      end
    end

    private

    attr_reader :project, :branch_name

    def branch_exists_locally?
      _out, _err, status = run([ "git", "rev-parse", "--verify", "--quiet", branch_name ])
      status.success?
    end

    def run(command)
      Open3.capture3(*command, chdir: project.local_directory)
    end

    def run!(command)
      out, err, status = run(command)
      raise CommandError, "#{command.join(' ')} failed: #{err.presence || out}" unless status.success?

      out
    end
  end
end
