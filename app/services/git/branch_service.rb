require "open3"

module Git
  # Creates (or resumes) a workflow's branch from `main` inside a project's
  # local checkout. Never shells out with a compound `cd X && ...` string —
  # always passes `chdir:` so this works the same whether the process's own
  # cwd is the orchestrator app or anything else.
  class BranchService
    def self.create_branch!(project, branch_name)
      new(project, branch_name).create!
    end

    # Review-fix flow: checkout main, pull main, checkout back to the branch
    # and merge main into it so the agent works on top of the latest main.
    # Returns :merged or :conflict (merge left in progress).
    def self.update_with_main!(project, branch_name)
      new(project, branch_name).update_with_main!
    end

    def initialize(project, branch_name)
      @project = project
      @branch_name = branch_name
    end

    def create!
      checkout_and_pull_main

      if branch_exists_locally?
        run!([ "git", "checkout", branch_name ])
      else
        run!([ "git", "checkout", "-b", branch_name ])
      end
    end

    def update_with_main!
      checkout_and_pull_main

      if branch_exists_locally?
        run!([ "git", "checkout", branch_name ])
      else
        run!([ "git", "checkout", "-b", branch_name, "origin/#{branch_name}" ])
      end

      merge_main!
    end

    def self.merge_in_progress?(project)
      _out, _err, status = Open3.capture3(*%w[git rev-parse -q --verify MERGE_HEAD], chdir: project.local_directory)
      status.success?
    end

    # Aborts an unfinished merge (agent failed to resolve) so the clone is clean.
    def self.abort_merge!(project)
      Open3.capture3(*%w[git merge --abort], chdir: project.local_directory) if merge_in_progress?(project)
    end

    private

    def checkout_and_pull_main
      run!(%w[git checkout main])
      run!(%w[git pull origin main])
    end

    # Returns :merged, or :conflict when the merge stopped on conflicts. The
    # conflicted merge is left in place for the agent to resolve. Any other
    # failure aborts the merge and raises.
    def merge_main!
      out, err, status = run(%w[git merge main --no-edit])
      return :merged if status.success?
      return :conflict if self.class.merge_in_progress?(project) && !conflicted_files.empty?

      run(%w[git merge --abort])
      raise CommandError, "git merge main failed: #{err.presence || out}"
    end

    def conflicted_files
      run!(%w[git diff --name-only --diff-filter=U]).split("\n")
    end

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
