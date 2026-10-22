require "json"

module Github
  # Query-only `gh` operations: PR state, checks, reviews and workflow runs.
  # Never changes anything on GitHub or in the clone.
  class Reader
    def initialize(project, runner: Runner.new(project))
      @project = project
      @runner = runner
    end

    def pr_url_for_branch(branch_name)
      pr_view(branch_name, "url")["url"]
    end

    # Finds the PR the implementation run opened; see Github::PrLocator.
    def find_pr_url(...)
      PrLocator.new(project, runner: runner).call(...)
    end

    # { "state" => "OPEN", "author" => "login", "head_ref" => "branch", "cross_repository" => false }
    def pr_info(pr_url)
      data = pr_view(pr_url, "state", "author", "headRefName", "isCrossRepository")
      {
        "state" => data["state"].to_s.upcase,
        "author" => data.dig("author", "login").to_s,
        "head_ref" => data["headRefName"].to_s,
        "cross_repository" => data["isCrossRepository"] == true
      }
    end

    def pr_title(pr_url)
      pr_view(pr_url, "title")["title"].to_s
    end

    # Login of the account `gh` is authenticated as.
    def current_login
      run!([ "gh", "api", "user", "--jq", ".login" ], scope_to_repo: false).strip
    end

    def merged?(pr_url)
      pr_view(pr_url, "state")["state"].to_s.upcase == "MERGED"
    end

    # "APPROVED", "CHANGES_REQUESTED", or nil (still waiting).
    #
    # With several reviewers assigned, any one of them approving is enough,
    # so we look at each assigned reviewer's latest review ourselves rather
    # than GitHub's `reviewDecision` (which reflects branch-protection rules
    # and can be blank or require every reviewer). Approval wins over a
    # pending change request.
    def review_decision(pr_url, reviewers)
      ReviewDecision.call(pr_view(pr_url, "latestReviews")["latestReviews"].to_a, reviewers)
    end

    # True if any GitHub check on the PR has finished in a failing state.
    # Checks still queued/in progress (no conclusion yet) are ignored.
    def checks_failing?(pr_url)
      FailingChecks.call(pr_view(pr_url, "statusCheckRollup")["statusCheckRollup"].to_a)
    end

    # State of the newest run of a GitHub Actions workflow (file name or name) that started at or after `since`,
    # in `repo` (default: the project's): { state: :none | :pending | :success | :failed, url: }.
    # :none = no such run yet (not dispatched / not visible yet), :pending = queued or in progress.
    def workflow_run_state(workflow, since:, repo: nil)
      repo = repo.presence || project.repo_full_name
      out = run!([ "gh", "run", "list", "--workflow", workflow, "--limit", "20", "--json", "status,conclusion,createdAt,url" ],
                 repo: repo)
      WorkflowRunState.call(JSON.parse(out), since: since)
    end

    private

    attr_reader :project, :runner

    def pr_view(ref, *fields)
      JSON.parse(run!([ "gh", "pr", "view", ref, "--json", fields.join(",") ]))
    end

    def run!(...)
      runner.run!(...)
    end
  end
end
