module Git
  # Task flow: publish whatever the agent committed on the current branch.
  # Returns :pushed, or :up_to_date when there is nothing ahead of origin.
  # A rejected push (origin moved) is retried once after a rebase; never forces.
  class Pusher
    def initialize(project = nil, shell: nil)
      @shell = shell || Shell.new(project.local_directory)
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

    private

    attr_reader :shell

    # Commits not on origin/<branch> (all of them when the branch isn't on origin yet).
    def ahead_count(branch)
      on_origin = shell.success?([ "git", "rev-parse", "--verify", "--quiet", "origin/#{branch}" ])
      range = on_origin ? "origin/#{branch}..HEAD" : "HEAD"
      shell.run!([ "git", "rev-list", "--count", range ]).to_i
    end
  end
end
