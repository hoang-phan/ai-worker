module Prompts
  module StageSections
    # Only the pr_check fix run, when reviewers are pinged in Slack: a short list of what was fixed for the thread reply.
    class FixedSummary
      def initialize(stage_type:, notify_enabled:)
        @stage_type = stage_type.to_s
        @notify_enabled = notify_enabled
      end

      def to_s
        return "" unless stage_type == "pr_check" && notify_enabled

        <<~SECTION

          Before your last line, print a short summary of what you fixed for the reviewers, one bullet per fix (at most 6, plain text, no markdown links), between lines containing only `FIXED_SUMMARY_BEGIN` and `FIXED_SUMMARY_END`.
        SECTION
      end

      private

      attr_reader :stage_type, :notify_enabled
    end
  end
end
