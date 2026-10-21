module Slack
  # Creates a PR-review workflow for every PR found in a Slack mention of the
  # project's configured handle. Idempotent: a (Slack message, PR) pair that
  # already has a workflow in this project (in any status) is skipped, as are
  # PRs that are no longer open or were authored by the account `gh` runs as
  # (you can't review your own PR).
  class ReviewSync
    # Kept for Slack::MentionFetcher.
    PR_URL = ReviewCandidate::PR_URL

    # skipped_reasons: { "merged" => 2, ... } — why PRs in `skipped` were not imported.
    Result = Struct.new(:blockers, :created, :skipped, :failed, :skipped_reasons, keyword_init: true) do
      def summary
        skipped_text = "skipped #{skipped.size}"
        skipped_text += " (#{skipped_reasons.map { |reason, count| "#{count} #{reason}" }.join(", ")})" if skipped_reasons.any?
        "created #{created.size}, #{skipped_text}, failed #{failed.size}"
      end
    end

    def initialize(project)
      @project = project
    end

    # Everything that would stop reviews from being created automatically.
    def blockers
      list = []
      list << "project kind is not jira" unless project.jira?
      list << "GitHub repo is not set" if project.repo_full_name.blank?
      list << "Slack mention is not set" if project.slack_mention.blank?
      list
    end

    def fetcher
      MentionFetcher.new(project)
    end

    # `mentions` is the array MentionFetcher#poll returns.
    def import(mentions)
      found = blockers
      return Result.new(blockers: found, created: [], skipped: [], failed: [], skipped_reasons: Hash.new(0)) if found.any?

      result = Result.new(blockers: [], created: [], skipped: [], failed: [], skipped_reasons: Hash.new(0))
      existing = project.workflows.pr_review.pluck(:slack_url, :github_pr_url).to_set
      github = Github::Client.new(project)
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

    attr_reader :project

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
