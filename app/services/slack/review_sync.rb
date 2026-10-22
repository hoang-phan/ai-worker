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

    def initialize(project, github: nil, fetcher: nil)
      @project = project
      @github = github
      @fetcher = fetcher
    end

    # Everything that would stop reviews from being created automatically.
    def blockers
      Projects::RunBlockers.new(project).messages(:jira_kind, :repo, :slack_mention)
    end

    def fetcher
      @fetcher ||= MentionFetcher.new(project)
    end

    # `mentions` is the array MentionFetcher#poll returns.
    def import(mentions)
      found = blockers
      return empty_result(found) if found.any?

      result = empty_result
      ReviewImporter.new(project, github: github).import(mentions, result)
    end

    private

    attr_reader :project

    def github
      @github ||= Github::Client.new(project)
    end

    def empty_result(blockers = [])
      Result.new(blockers: blockers, created: [], skipped: [], failed: [], skipped_reasons: Hash.new(0))
    end
  end
end
