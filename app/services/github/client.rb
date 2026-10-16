require "open3"
require "json"

module Github
  # Thin wrapper around the `gh` CLI. Read-only PR state plus the one
  # write operation this app needs that has no plain `gh pr` subcommand:
  # re-requesting a review via the REST API.
  #
  # PR *creation* is not done here — the implementation stage's prompt
  # instructs the agent to run `gh pr create` itself as part of the coding run.
  class Client
    # `workflow.github_reviewer` holds one or more usernames, comma-separated.
    def self.parse_reviewers(value)
      value.to_s.split(/[,\s]+/).reject(&:blank?).uniq
    end

    def initialize(project)
      @project = project
    end

    def pr_url_for_branch(branch_name)
      out = run!([ "gh", "pr", "view", branch_name, "--json", "url" ])
      JSON.parse(out)["url"]
    end

    # Finds the PR the implementation run opened. the agent may push to a branch
    # named differently from `workflow.branch_name` (e.g. `bug/ENG-1/slug` per
    # the target repo's conventions), so try, in order: the PR URL the agent
    # printed, the workflow's own branch name, then any open PR whose head
    # branch contains the Jira ticket.
    def find_pr_url(branch_name:, jira_ticket:, output: nil)
      url_from_output(output) ||
        url_for_head(branch_name) ||
        url_for_ticket(jira_ticket) ||
        raise(CommandError, "agent finished but no PR was found (branch=#{branch_name.inspect}, ticket=#{jira_ticket.inspect})")
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

    # Login of the account `gh` is authenticated as.
    def current_login
      run!([ "gh", "api", "user", "--jq", ".login" ], scope_to_repo: false).strip
    end

    # Fetches a PR (including fork PRs) into the clone and checks it out, for
    # the rare case it can't be done with plain git.
    def checkout_pr!(pr_url)
      run!([ "gh", "pr", "checkout", pr_url ])
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

    FAILED_CONCLUSIONS = %w[FAILURE TIMED_OUT STARTUP_FAILURE ACTION_REQUIRED].freeze
    FAILED_STATES = %w[FAILURE ERROR].freeze

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

    def request_review!(pr_url, reviewers)
      number = pr_number(pr_url)
      run!([
        "gh", "api",
        "repos/#{project.repo_full_name}/pulls/#{number}/requested_reviewers",
        *Array(reviewers).flat_map { |reviewer| [ "-f", "reviewers[]=#{reviewer}" ] }
      ], scope_to_repo: false)
    end

    # Turns on GitHub auto-merge: the PR merges itself once required reviews
    # and checks pass. Requires "Allow auto-merge" on the repo.
    def enable_auto_merge!(pr_url)
      run!([ "gh", "pr", "merge", pr_url, "--auto", "--merge" ])
    end

    private

    attr_reader :project

    # Last PR URL for this project's repo printed in the agent's output.
    def url_from_output(output)
      pattern = %r{https://github\.com/#{Regexp.escape(project.repo_full_name)}/pull/\d+}i
      output.to_s.scan(pattern).last
    end

    def url_for_head(branch_name)
      return if branch_name.blank?

      JSON.parse(run!([ "gh", "pr", "view", branch_name, "--json", "url" ]))["url"]
    rescue CommandError
      nil
    end

    def url_for_ticket(jira_ticket)
      key = jira_ticket.to_s[/[A-Z][A-Z0-9]+-\d+/i]
      return unless key

      out = run!([ "gh", "pr", "list", "--state", "open", "--limit", "100", "--json", "url,headRefName" ])
      prs = JSON.parse(out).select { |pr| pr["headRefName"].to_s.downcase.include?(key.downcase) }
      prs.first&.dig("url")
    end

    def pr_number(pr_url)
      pr_url.to_s[%r{/pull/(\d+)}, 1] or raise CommandError, "could not parse PR number from #{pr_url}"
    end

    # `gh api` has no `-R` flag (the repo is part of its endpoint path), so
    # callers of it pass `scope_to_repo: false`.
    def run!(command, scope_to_repo: true, repo: project.repo_full_name)
      command = [ *command, "-R", repo ] if scope_to_repo
      out, err, status = Open3.capture3(*command, chdir: project.local_directory)
      raise CommandError, "#{command.join(' ')} failed: #{err.presence || out}" unless status.success?

      out
    end
  end
end
