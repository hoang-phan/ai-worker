module Slack
  # Imports PRs found in Slack mentions as pr_review workflows, recording the
  # outcome of each PR on the Result it is given. Idempotent per
  # (slack_url, pr_url) pair within the project.
  class ReviewImporter
    def initialize(project, github: Github::Client.new(project))
      @project = project
      @github = github
    end

    # `mentions` is the array MentionFetcher#poll returns; `result` is mutated and returned.
    def import(mentions, result)
      existing = project.workflows.pr_review.pluck(:slack_url, :github_pr_url).to_set
      @current_login = nil

      mentions.each do |mention|
        mention["pr_urls"].each { |pr_url| import_pr(mention["slack_url"], pr_url, existing, result) }
      end
      result
    end

    private

    attr_reader :project, :github

    def import_pr(slack_url, pr_url, existing, result)
      return unless ReviewCandidate.own_repo?(pr_url, project.repo_full_name)

      if existing.include?([ slack_url, pr_url ])
        skip(result, pr_url, "already imported")
        return
      end

      info = github.pr_info(pr_url)
      if (reason = ReviewCandidate.skip_reason(info: info, current_login: current_login))
        skip(result, pr_url, reason)
      else
        create_workflow(slack_url, pr_url, result)
      end
      existing << [ slack_url, pr_url ]
    rescue Github::CommandError => e
      result.failed << "#{pr_url}: #{e.message}"
    end

    # Read lazily (only once a PR needs it), at most once per #import call.
    def current_login
      @current_login ||= github.current_login
    end

    def skip(result, pr_url, reason)
      result.skipped << pr_url
      result.skipped_reasons[reason] += 1
    end

    def create_workflow(slack_url, pr_url, result)
      workflow = project.workflows.new(
        kind: :pr_review,
        status: :implementing,
        slack_url: slack_url,
        github_pr_url: pr_url,
        position: project.next_workflow_position
      )
      result.record_save(workflow, pr_url)
    end
  end
end
