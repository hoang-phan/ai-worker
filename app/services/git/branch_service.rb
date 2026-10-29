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

    # CI flow: the clone is shared with other workflows (a PR review leaves it on someone else's branch), so put it
    # back on the workflow's own local branch before anything runs against HEAD. No-op when already there.
    def self.ensure_on_branch!(project, branch_name)
      new(project, branch_name).ensure_on_branch!
    end

    # Task flow: publish whatever the agent committed on the current branch.
    # Returns :pushed, or :up_to_date when there is nothing ahead of origin.
    # A rejected push (origin moved) is retried once after a rebase; never forces.
    def self.push_current!(project)
      Pusher.new(project).push_current!
    end

    def self.merge_in_progress?(project)
      MergeState.new(project).merge_in_progress?
    end

    # Aborts an unfinished merge (agent failed to resolve) so the clone is clean.
    def self.abort_merge!(project)
      MergeState.new(project).abort_merge!
    end

    def initialize(project, branch_name, shell: nil, merge_state: nil)
      @project = project
      @branch_name = branch_name
      @shell = shell || Shell.new(project.local_directory)
      @merge_state = merge_state || MergeState.new(project, shell: @shell)
    end

    def create!
      checkout_and_pull_main
      checkout_branch!
    end

    def update_with_main!
      checkout_and_pull_main
      checkout_branch!(start_point: "origin/#{branch_name}")
      merge_state.merge_main!
    end

    def checkout_remote!
      shell.run!([ "git", "fetch", "origin", branch_name ])
      existed = checkout_branch!(start_point: "origin/#{branch_name}")
      shell.run!([ "git", "pull", "--ff-only", "origin", branch_name ]) if existed
    end

    def ensure_on_branch!
      return if shell.run!([ "git", "rev-parse", "--abbrev-ref", "HEAD" ]).strip == branch_name

      shell.checkout!([ "git", "checkout", branch_name ])
    end

    private

    attr_reader :project, :branch_name, :shell, :merge_state

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

    def checkout_and_pull_main
      shell.checkout!(%w[git checkout main])
      shell.run!(%w[git pull origin main])
    end

    def branch_exists_locally?
      shell.success?([ "git", "rev-parse", "--verify", "--quiet", branch_name ])
    end
  end
end
