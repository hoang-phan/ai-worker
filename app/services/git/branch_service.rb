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
        checkout!([ "git", "checkout", branch_name ])
      else
        checkout!([ "git", "checkout", "-b", branch_name ])
      end
    end

    def update_with_main!
      checkout_and_pull_main

      if branch_exists_locally?
        checkout!([ "git", "checkout", branch_name ])
      else
        checkout!([ "git", "checkout", "-b", branch_name, "origin/#{branch_name}" ])
      end

      merge_main!
    end

    # Review flow: put the clone on a PR's head branch, up to date with origin,
    # so the agent can read the code in context. Never discards local commits
    # (fast-forward only) — a diverged branch fails the stage. A dirty tree that
    # blocks checkout is auto-stashed and the checkout retried.
    def self.checkout_remote_branch!(project, branch_name)
      new(project, branch_name).checkout_remote!
    end

    def checkout_remote!
      run!([ "git", "fetch", "origin", branch_name ])
      if branch_exists_locally?
        checkout!([ "git", "checkout", branch_name ])
        run!([ "git", "pull", "--ff-only", "origin", branch_name ])
      else
        checkout!([ "git", "checkout", "-b", branch_name, "origin/#{branch_name}" ])
      end
    end

    # Task flow: publish whatever the agent committed on the current branch.
    # Returns :pushed, or :up_to_date when there is nothing ahead of origin.
    # A rejected push (origin moved) is retried once after a rebase; never forces.
    def self.push_current!(project)
      new(project, nil).push_current!
    end

    def push_current!
      branch = run!(%w[git rev-parse --abbrev-ref HEAD]).strip
      return :up_to_date if ahead_count(branch).zero?

      _out, _err, status = run([ "git", "push", "origin", "HEAD" ])
      unless status.success?
        run!([ "git", "pull", "--rebase", "origin", branch ])
        run!([ "git", "push", "origin", "HEAD" ])
      end
      :pushed
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

    # Commits not on origin/<branch> (all of them when the branch isn't on origin yet).
    def ahead_count(branch)
      _out, _err, status = run([ "git", "rev-parse", "--verify", "--quiet", "origin/#{branch}" ])
      range = status.success? ? "origin/#{branch}..HEAD" : "HEAD"
      run!([ "git", "rev-list", "--count", range ]).to_i
    end

    def checkout_and_pull_main
      checkout!(%w[git checkout main])
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

    # Runs a `git checkout`. If it is refused because local changes (tracked or
    # untracked) would be overwritten, stashes them (nothing is discarded —
    # recover with `git stash list` / `git stash pop`) and retries once.
    def checkout!(command)
      out, err, status = run(command)
      return out if status.success?

      unless err.match?(/would be overwritten by checkout/)
        raise CommandError, "#{command.join(' ')} failed: #{err.presence || out}"
      end

      run!([ "git", "stash", "push", "--include-untracked", "-m", "ai-worker: auto-stash before #{command.join(' ')}" ])
      run!(command)
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
