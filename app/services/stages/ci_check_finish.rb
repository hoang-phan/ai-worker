module Stages
  # The CI command exited (any status): keep its log for the verify stage and hand over to it. A failing check is a
  # result, not an error; the verify stage decides what it means.
  class CiCheckFinish
    TAIL_BYTES = 3000

    def initialize(workflow:, stage:)
      @workflow = workflow
      @stage = stage
    end

    def call(exit_status)
      log_path = workflow.ai_log_path
      workflow.finish_ai_run!(status: :ci_verifying, ci_output_path: log_path, ci_exit_status: exit_status)
      stage.log_run!("ci_check_completed", output: "exit status #{exit_status}\n#{tail(log_path)}")
    end

    private

    attr_reader :workflow, :stage

    def tail(path)
      return "" unless path && File.exist?(path)

      File.open(path) do |file|
        file.seek([ file.size - TAIL_BYTES, 0 ].max)
        file.read.to_s.scrub
      end
    end
  end
end
