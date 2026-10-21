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
      ReviewImporter.new(project, github: Github::Client.new(project)).import(mentions, result)
    end

    private

    attr_reader :project
  end
end
