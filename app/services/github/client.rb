module Github
  # Backwards-compatible facade over the `gh` CLI collaborators:
  #   Github::Reader - query-only PR/check/review/workflow-run operations
  #   Github::Writer - side-effecting operations (request review, auto-merge, checkout)
  # Both share a Github::Runner, which owns command construction and error translation.
  class Client
    FAILED_CONCLUSIONS = Reader::FAILED_CONCLUSIONS
    FAILED_STATES = Reader::FAILED_STATES

    # `workflow.github_reviewer` holds one or more usernames, comma-separated.
    def self.parse_reviewers(value)
      value.to_s.split(/[,\s]+/).reject(&:blank?).uniq
    end

    attr_reader :reader, :writer

    def initialize(project, reader: nil, writer: nil)
      runner = Runner.new(project)
      @reader = reader || Reader.new(project, runner: runner)
      @writer = writer || Writer.new(project, runner: runner)
    end

    delegate :pr_url_for_branch, :find_pr_url, :pr_info, :pr_title, :current_login, :merged?,
             :review_decision, :checks_failing?, :workflow_run_state, to: :reader
    delegate :checkout_pr!, :request_review!, :enable_auto_merge!, to: :writer
  end
end
