module Brainstorm
  # What a finished brainstorm run left in its agent.log (stream-json output) when it wrote no result.json:
  # the final valid `result` event, whether to retry the run, and why it failed. Result-event parsing belongs to
  # AiCli::ClaudeResult (AiCli::Output forwards to it). Read-only; RunLifecycle owns the `retried` marker file and the relaunch.
  class RunOutcome
    def initialize(log_path:, retried:)
      @log_path = Pathname(log_path)
      @retried = retried
    end

    # The agent's final valid `result` event, or nil if there is none.
    def event
      return @event if defined?(@event)

      @event = read_event
    end

    # A run that died because its API stream was cut is retried once, right away, instead of waiting for the next tick.
    def retry?
      !!event && event["terminal_reason"] == "aborted_streaming" && !@retried
    end

    def failure_reason
      return "no result event in the log" unless event

      [ event["subtype"], event["terminal_reason"] ].compact.join("/")
    end

    private

    def read_event
      return unless @log_path.exist?

      AiCli::Output.new(@log_path.read).result_event
    end
  end
end
