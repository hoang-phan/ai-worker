require "open3"
require "json"

module Github
  class CommandError < StandardError; end

  # Thin wrapper around the `gh` CLI. Read-only PR state plus the one
  # write operation this app needs that has no plain `gh pr` subcommand:
  # re-requesting a review via the REST API.
  #
  # PR *creation* is not done here — the implementation stage's prompt
  # instructs Claude to run `gh pr create` itself as part of the coding run.
  class Client
    def initialize(project)
      @project = project
    end

    def pr_url_for_branch(branch_name)
      out = run!([ "gh", "pr", "view", branch_name, "--json", "url" ])
      JSON.parse(out)["url"]
    end

    # "APPROVED", "CHANGES_REQUESTED", "REVIEW_REQUIRED", or nil
    def review_decision(pr_url)
      out = run!([ "gh", "pr", "view", pr_url, "--json", "reviewDecision" ])
      JSON.parse(out)["reviewDecision"].presence
    end

    def request_review!(pr_url, reviewer)
      number = pr_number(pr_url)
      run!([
        "gh", "api",
        "repos/#{project.repo_full_name}/pulls/#{number}/requested_reviewers",
        "-f", "reviewers[]=#{reviewer}"
      ])
    end

    private

    attr_reader :project

    def pr_number(pr_url)
      pr_url.to_s[%r{/pull/(\d+)}, 1] or raise CommandError, "could not parse PR number from #{pr_url}"
    end

    def run!(command)
      out, err, status = Open3.capture3(*command, "-R", project.repo_full_name, chdir: project.local_directory)
      raise CommandError, "#{command.join(' ')} failed: #{err.presence || out}" unless status.success?

      out
    end
  end
end
