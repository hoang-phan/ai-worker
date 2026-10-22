module Prompts
  module StageSections
    # Only the pr_check fix run: asks for the generalisable rules the review taught, which Stages::PrCheckFinish keeps
    # in project.agent_lessons for later implementation runs.
    class LessonsRequest
      def initialize(stage_type:)
        @stage_type = stage_type.to_s
      end

      def to_s
        return "" unless stage_type == "pr_check"

        <<~SECTION

          Before your final line(s), print 0-3 generalisable rules for this project that you learned from this review (one line each, imperative, not specific to this PR, e.g. `Use the shared error_summary partial on forms`) between lines containing only `LESSONS_BEGIN` and `LESSONS_END`, or print nothing if there are none.
        SECTION
      end

      private

      attr_reader :stage_type
    end
  end
end
