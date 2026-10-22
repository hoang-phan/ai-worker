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

    # Review flow: put the clone on a PR's head branch, up to date with origin,
    # so the agent can read the code in context. Never discards local commits
    # (fast-forward only) — a diverged branch fails the stage. A dirty tree that
    # blocks checkout is auto-stashed and the checkout retried.
    def self.checkout_remote_branch!(project, branch_name)
      new(project, branch_name).checkout_remote!
    end

    # Task flow: publish whatever the agent committed on the current branch.
    # Returns :pushed, or :up_to_date when there is nothing ahead of origin.
    # A rejected push (origin moved) is retried once after a rebase; never forces.
    def self.push_current!(project)
      new(project, nil).push_current!
    end

    def self.merge_in_progress?(project)
      new(project, nil).merge_in_progress?
    end

    # Aborts an unfinished merge (agent failed to resolve) so the clone is clean.
    def self.abort_merge!(project)
      new(project, nil).abort_merge!
    end

    def initialize(project, branch_name)
      @project = project
      @branch_name = branch_name
      @shell = Shell.new(project.local_directory)
    end

    def create!
      checkout_and_pull_main
      checkout_branch!
    end

    def update_with_main!
      checkout_and_pull_main
      checkout_branch!(start_point: "origin/#{branch_name}")
      merge_main!
    end

    def checkout_remote!
      shell.run!([ "git", "fetch", "origin", branch_name ])
      existed = checkout_branch!(start_point: "origin/#{branch_name}")
      shell.run!([ "git", "pull", "--ff-only", "origin", branch_name ]) if existed
    end

    def push_current!
      branch = shell.run!(%w[git rev-parse --abbrev-ref HEAD]).strip
      return :up_to_date if ahead_count(branch).zero?

      unless shell.success?([ "git", "push", "origin", "HEAD" ])
        shell.run!([ "git", "pull", "--rebase", "origin", branch ])
        shell.run!([ "git", "push", "origin", "HEAD" ])
      end
      :pushed
    end

    def merge_in_progress?
      shell.success?(%w[git rev-parse -q --verify MERGE_HEAD])
    end

    def abort_merge!
      shell.run(%w[git merge --abort]) if merge_in_progress?
    end

    private

    attr_reader :project, :branch_name, :shell

    # Checks out the branch, creating it (from start_point when given) if it
    # isn't local yet. Returns true when the branch already existed locally.
    def checkout_branch!(start_point: nil)
      if branch_exists_locally?
        shell.checkout!([ "git", "checkout", branch_name ])
        true
      else
        shell.checkout!([ "git", "checkout", "-b", branch_name, *start_point ])
        false
      end
    end

    # Commits not on origin/<branch> (all of them when the branch isn't on origin yet).
    def ahead_count(branch)
      on_origin = shell.success?([ "git", "rev-parse", "--verify", "--quiet", "origin/#{branch}" ])
      range = on_origin ? "origin/#{branch}..HEAD" : "HEAD"
      shell.run!([ "git", "rev-list", "--count", range ]).to_i
    end

    def checkout_and_pull_main
      shell.checkout!(%w[git checkout main])
      shell.run!(%w[git pull origin main])
    end

    # Returns :merged, or :conflict when the merge stopped on conflicts. The
    # conflicted merge is left in place for the agent to resolve. Any other
    # failure aborts the merge and raises.
    def merge_main!
      out, err, status = shell.run(%w[git merge main --no-edit])
      return :merged if status.success?
      return :conflict if merge_in_progress? && !conflicted_files.empty?

      shell.run(%w[git merge --abort])
      raise CommandError, "git merge main failed: #{err.presence || out}"
    end

    def conflicted_files
      shell.run!(%w[git diff --name-only --diff-filter=U]).split("\n")
    end

    def branch_exists_locally?
      shell.success?([ "git", "rev-parse", "--verify", "--quiet", branch_name ])
    end
  end
end
