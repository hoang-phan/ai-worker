require "json"

module Github
  # Query-only `gh` operations: PR state, checks, reviews and workflow runs.
  # Never changes anything on GitHub or in the clone.
  class Reader
    FAILED_CONCLUSIONS = %w[FAILURE TIMED_OUT STARTUP_FAILURE ACTION_REQUIRED].freeze
    FAILED_STATES = %w[FAILURE ERROR].freeze

    def initialize(project, runner: Runner.new(project))
      @project = project
      @runner = runner
    end

    def pr_url_for_branch(branch_name)
      out = run!([ "gh", "pr", "view", branch_name, "--json", "url" ])
      JSON.parse(out)["url"]
    end

    # Finds the PR the implementation run opened; see Github::PrLocator.
    def find_pr_url(...)
      PrLocator.new(project, runner: runner).call(...)
    end

    # { "state" => "OPEN", "author" => "login", "head_ref" => "branch", "cross_repository" => false }
    def pr_info(pr_url)
      data = JSON.parse(run!([ "gh", "pr", "view", pr_url, "--json", "state,author,headRefName,isCrossRepository" ]))
      {
        "state" => data["state"].to_s.upcase,
        "author" => data.dig("author", "login").to_s,
        "head_ref" => data["headRefName"].to_s,
        "cross_repository" => data["isCrossRepository"] == true
      }
    end

    def pr_title(pr_url)
      JSON.parse(run!([ "gh", "pr", "view", pr_url, "--json", "title" ]))["title"].to_s
    end

    # Login of the account `gh` is authenticated as.
    def current_login
      run!([ "gh", "api", "user", "--jq", ".login" ], scope_to_repo: false).strip
    end

    def merged?(pr_url)
      out = run!([ "gh", "pr", "view", pr_url, "--json", "state" ])
      JSON.parse(out)["state"].to_s.upcase == "MERGED"
    end

    # "APPROVED", "CHANGES_REQUESTED", or nil (still waiting).
    #
    # With several reviewers assigned, any one of them approving is enough,
    # so we look at each assigned reviewer's latest review ourselves rather
    # than GitHub's `reviewDecision` (which reflects branch-protection rules
    # and can be blank or require every reviewer). Approval wins over a
    # pending change request.
    def review_decision(pr_url, reviewers)
      out = run!([ "gh", "pr", "view", pr_url, "--json", "latestReviews" ])
      wanted = reviewers.map(&:downcase)
      states = JSON.parse(out)["latestReviews"].to_a.filter_map do |review|
        login = review.dig("author", "login").to_s.downcase
        review["state"] if wanted.empty? || wanted.include?(login)
      end

      return "APPROVED" if states.include?("APPROVED")
      return "CHANGES_REQUESTED" if states.include?("CHANGES_REQUESTED")

      nil
    end

    # True if any GitHub check on the PR has finished in a failing state.
    # Checks still queued/in progress (no conclusion yet) are ignored.
    def checks_failing?(pr_url)
      out = run!([ "gh", "pr", "view", pr_url, "--json", "statusCheckRollup" ])
      JSON.parse(out)["statusCheckRollup"].to_a.any? do |check|
        FAILED_CONCLUSIONS.include?(check["conclusion"].to_s.upcase) ||
          FAILED_STATES.include?(check["state"].to_s.upcase)
      end
    end

    # State of the newest run of a GitHub Actions workflow (file name or name) that started at or after `since`,
    # in `repo` (default: the project's): { state: :none | :pending | :success | :failed, url: }.
    # :none = no such run yet (not dispatched / not visible yet), :pending = queued or in progress.
    def workflow_run_state(workflow, since:, repo: nil)
      repo = repo.presence || project.repo_full_name
      out = run!([ "gh", "run", "list", "--workflow", workflow, "--limit", "20", "--json", "status,conclusion,createdAt,url" ],
                 repo: repo)
      run = JSON.parse(out).select { |r| Time.zone.parse(r["createdAt"].to_s) >= since }.max_by { |r| r["createdAt"] }
      return { state: :none } unless run
      return { state: :pending, url: run["url"] } unless run["status"].to_s.casecmp?("completed")

      { state: run["conclusion"].to_s.casecmp?("success") ? :success : :failed, url: run["url"], conclusion: run["conclusion"] }
    end

    private

    attr_reader :project, :runner

    def run!(...)
      runner.run!(...)
    end
  end
end
