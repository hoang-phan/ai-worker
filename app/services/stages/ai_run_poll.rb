module Stages
  # Polls a detached run and keeps the workflow's log cursor durable between scheduler ticks.
  class AiRunPoll
    def initialize(workflow:, stage:, poller_class:, stale_after:)
      @workflow = workflow
      @stage = stage
      @poller_class = poller_class
      @stale_after = stale_after
    end

    # Returns the completed output, or nil while the run is still going.
    def call
      poller = poller_class.new(
        pid: workflow.ai_pid, log_path: workflow.ai_log_path, log_offset: workflow.ai_log_offset,
        started_at: workflow.ai_started_at, log_tag: log_tag, stale_after: stale_after,
        provider: workflow.ai_provider
      )
      begin
        state, output = poller.call
      ensure
        workflow.update_column(:ai_log_offset, poller.log_offset) if poller.log_offset != workflow.ai_log_offset
      end
      output unless state == :running
    end

    private

    attr_reader :workflow, :stage, :poller_class, :stale_after

    def log_tag
      "workflow=#{workflow.id} stage=#{stage.id}"
    end
  end
end
