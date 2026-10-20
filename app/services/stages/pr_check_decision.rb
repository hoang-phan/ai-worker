module Stages
  # Decides what a pr_check stage should do from the PR's review decision, any
  # pending local-test failure and (lazily) the PR's CI state. Pure logic: no
  # workflow, git or gh access, so StageExecutor keeps only the side effects.
  class PrCheckDecision
    Result = Struct.new(:decision, :actions, keyword_init: true)

    # review_decision     - Github::Client#review_decision string (may be nil/other)
    # local_test_failing  - truthy when the workflow has pending local-test feedback
    # checks_failing      - callable returning whether CI is failing; only called
    #                       when the decision is still APPROVED
    def initialize(review_decision:, local_test_failing:, checks_failing:)
      @review_decision = review_decision
      @local_test_failing = local_test_failing
      @checks_failing = checks_failing
    end

    # => Result with decision :approved / :changes_requested / :pending and the
    # StageRun actions to log (in order) on the way.
    def call
      decision = review_decision
      actions = []

      # A failed local test waits for the review (requested changes may make its findings obsolete), then is fixed in
      # the same run as the review feedback; an approval can't close the workflow over it.
      if local_test_failing && %w[APPROVED CHANGES_REQUESTED].include?(decision)
        actions << "local_test_failing"
        decision = "CHANGES_REQUESTED"
      end

      # An approval with failing checks is treated like a change request.
      if decision == "APPROVED" && checks_failing.call
        actions << "checks_failing"
        decision = "CHANGES_REQUESTED"
      end

      Result.new(decision: normalize(decision), actions: actions)
    end

    private

    attr_reader :review_decision, :local_test_failing, :checks_failing

    def normalize(decision)
      case decision
      when "APPROVED" then :approved
      when "CHANGES_REQUESTED" then :changes_requested
      else :pending
      end
    end
  end
end
