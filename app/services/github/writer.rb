module Github
  # Side-effecting `gh` operations: re-requesting reviews, enabling auto-merge
  # and checking a PR out into the clone.
  #
  # PR *creation* is not done here — the implementation stage's prompt
  # instructs the agent to run `gh pr create` itself as part of the coding run.
  class Writer
    def initialize(project, runner: Runner.new(project))
      @project = project
      @runner = runner
    end

    # Fetches a PR (including fork PRs) into the clone and checks it out, for
    # the rare case it can't be done with plain git.
    def checkout_pr!(pr_url)
      runner.run!([ "gh", "pr", "checkout", pr_url ])
    end

    def request_review!(pr_url, reviewers)
      number = pr_number(pr_url)
      runner.run!([
        "gh", "api",
        "repos/#{project.repo_full_name}/pulls/#{number}/requested_reviewers",
        *Array(reviewers).flat_map { |reviewer| [ "-f", "reviewers[]=#{reviewer}" ] }
      ], scope_to_repo: false)
    end

    # Turns on GitHub auto-merge: the PR merges itself once required reviews
    # and checks pass. Requires "Allow auto-merge" on the repo.
    def enable_auto_merge!(pr_url)
      runner.run!([ "gh", "pr", "merge", pr_url, "--auto", "--merge" ])
    end

    private

    attr_reader :project, :runner

    def pr_number(pr_url)
      pr_url.to_s[%r{/pull/(\d+)}, 1] or raise CommandError, "could not parse PR number from #{pr_url}"
    end
  end
end
