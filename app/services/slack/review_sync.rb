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
    Result = AgentRuns::ImportResult

    def initialize(project, github: nil, fetcher: nil,
                   github_factory: -> { Github::Client.new(project) },
                   importer: ->(github) { ReviewImporter.new(project, github: github) })
      @project = project
      @github = github
      @fetcher = fetcher
      @github_factory = github_factory
      @importer = importer
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
      return Result.empty(found) if found.any?

      result = Result.empty
      importer.call(github).import(mentions, result)
    end

    private

    attr_reader :project, :github_factory, :importer

    def github
      return @github unless @github.nil?

      @github = github_factory.call
    end
  end
end
