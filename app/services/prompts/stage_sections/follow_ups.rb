module Prompts
  module StageSections
    # Only task runs: out-of-scope work the agent finds is handed over as follow-ups (Stages::TaskFinish queues a
    # workflow for each) instead of being done here or dropped.
    class FollowUps
      def initialize(stage_type:)
        @stage_type = stage_type.to_s
      end

      def to_s
        return "" unless stage_type == "task"

        <<~SECTION

          If you discovered necessary work that is outside the scope of this task, do not do it here. Instead, before your final line(s), list at most 2 such follow-ups as a JSON array of objects with "summary" (one short line) and "task" (self-contained text for another agent: what to do, where, and how to verify it), between lines containing only `FOLLOW_UPS_BEGIN` and `FOLLOW_UPS_END`. Omit the block if there are none.
        SECTION
      end

      private

      attr_reader :stage_type
    end
  end
end
