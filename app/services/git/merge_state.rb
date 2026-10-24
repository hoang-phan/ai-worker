module Git
  # Merge state of a project's clone: merging `main` into the current branch,
  # detecting an unfinished merge and aborting it.
  class MergeState
    def initialize(project = nil, shell: nil)
      @shell = shell || Shell.new(project.local_directory)
    end

    def merge_in_progress?
      shell.success?(%w[git rev-parse -q --verify MERGE_HEAD])
    end

    # Aborts an unfinished merge (agent failed to resolve) so the clone is clean.
    def abort_merge!
      shell.run(%w[git merge --abort]) if merge_in_progress?
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

    private

    attr_reader :shell

    def conflicted_files
      shell.run!(%w[git diff --name-only --diff-filter=U]).split("\n")
    end
  end
end
