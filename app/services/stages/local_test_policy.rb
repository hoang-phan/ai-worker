module Stages
  # Pure local-test retry and outcome rules. StageExecutor supplies the workflow
  # state and performs the resulting database, GitHub, and notification work.
  class LocalTestPolicy
    # A FAILED local test is fixed by the next pr_check run and then tested again,
    # at most this many tests in total.
    MAX_LOCAL_TEST_ROUNDS = 3

    Outcome = Struct.new(:failed, :retest, :rounds_exhausted, :auto_merge, keyword_init: true) do
      def failed? = failed
      def retest? = retest
      def rounds_exhausted? = rounds_exhausted
      def auto_merge? = auto_merge
    end

    class << self
      # A fix run is retested only when local testing remains configured, there
      # is still a round available, and either a failure is pending or the agent
      # asks for one (a missing LOCAL_RETEST marker is parsed as requested).
      def retest_after_fix?(local_test_ready:, completed_rounds:, feedback_pending:, retest_requested:)
        return false unless local_test_ready
        return false if completed_rounds >= MAX_LOCAL_TEST_ROUNDS

        feedback_pending || retest_requested
      end

      # completed_rounds is the number before the just-finished local test.
      def outcome(result:, completed_rounds:)
        failed = result.to_s.casecmp?("FAILED")
        retest = failed && completed_rounds + 1 < MAX_LOCAL_TEST_ROUNDS

        Outcome.new(
          failed: failed,
          retest: retest,
          rounds_exhausted: failed && !retest,
          auto_merge: result.to_s.casecmp?("PASSED")
        )
      end

      def feedback(output_block:, pr_url:)
        output_block || "Local testing failed; see the \"Local test by agent\" comment on #{pr_url} for the failing steps."
      end
    end
  end
end
