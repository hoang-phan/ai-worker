module Prompts
  module StageSections
    # Implementation and review-fix runs run the project's checks (CI, test suites) several times. Their passing output
    # (per-test lines, console noise, stack traces) is what burns most of the agent's tokens and time, and a transient
    # failure used to send it back to rerun the whole multi-minute gate from the start.
    class CheckOutput
      def initialize(stage_type:)
        @stage_type = stage_type.to_s
      end

      def to_s
        return "" unless %w[implementation pr_check].include?(stage_type)

        <<~SECTION

          Running checks (CI, linters, test suites): unless the project's instructions say the command already prints
          compact output, redirect each command's full output to a file under tmp/ (e.g.
          `bin/ci > tmp/ci.log 2>&1`, in the background if it takes minutes), wait for it to exit, then read only the
          verdict and the failures (`tail -n 40`, `grep -nE "FAIL|●|Failures:|rspec ./|error"`). Never print a whole
          passing run, and prefer quiet reporters where the tool has one (e.g. jest `--silent` with a summary or
          failures-only reporter, rspec progress format).
          When a check fails, do not restart the whole gate. Re-run only the failing files or examples on their own (one
          worker, no other load) and fix from there; a timeout that passes in isolation is load-related, not a defect
          in your change. Run the full gate once more, only after those fixes and any other edits are committed, and
          read that run's tail rather than its log. A run that times out or is killed is a reason to narrow it down, not
          to repeat it unchanged.
        SECTION
      end

      private

      attr_reader :stage_type
    end
  end
end
