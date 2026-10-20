module Slack
  # Pure decision about whether a PR found in a Slack mention should become a
  # review workflow. No GitHub or database access.
  class ReviewCandidate
    PR_URL = %r{\Ahttps://github\.com/([^/\s]+)/([^/\s]+)/pull/\d+\z}

    # True when pr_url is a PR URL in repo_full_name (case-insensitive);
    # nil for a URL that is not a GitHub PR URL.
    def self.own_repo?(pr_url, repo_full_name)
      pr_url[PR_URL, 0]&.then { "#{$1}/#{$2}".casecmp?(repo_full_name) }
    end

    # nil when the PR should be imported, otherwise the reason it is skipped.
    def self.skip_reason(info:, current_login:)
      return info["state"].downcase if info["state"] != "OPEN"

      "own PR" if info["author"].casecmp?(current_login)
    end
  end
end
