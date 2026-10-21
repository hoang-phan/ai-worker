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
      me = nil

      mentions.each do |mention|
        mention["pr_urls"].each do |pr_url|
          next unless ReviewCandidate.own_repo?(pr_url, project.repo_full_name)

          if existing.include?([ mention["slack_url"], pr_url ])
            skip(result, pr_url, "already imported")
            next
          end

          info = github.pr_info(pr_url)
          me ||= github.current_login
          if (reason = ReviewCandidate.skip_reason(info: info, current_login: me))
            skip(result, pr_url, reason)
          else
            create_workflow(mention["slack_url"], pr_url, result)
          end
          existing << [ mention["slack_url"], pr_url ]
        rescue Github::CommandError => e
          result.failed << "#{pr_url}: #{e.message}"
        end
      end
      result
    end

    private

    attr_reader :project, :github

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
      if workflow.save
        result.created << pr_url
      else
        result.failed << "#{pr_url}: #{workflow.errors.full_messages.to_sentence}"
      end
    end
  end
end
