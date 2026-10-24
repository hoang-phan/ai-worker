require "json"

module Brainstorm
  # What a finished brainstorm run left in its agent.log (stream-json output) when it wrote no result.json:
  # the final `result` event, whether to retry the run, and why it failed. Read-only; RunLifecycle owns the
  # `retried` marker file and the relaunch.
  class RunOutcome
    def initialize(log_path:, retried:)
      @log_path = Pathname(log_path)
      @retried = retried
    end

    # The agent's final `result` event, or nil if there is none (or the line is not valid JSON).
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

      @log_path.each_line.reverse_each do |line|
        next unless line.start_with?('{"type":"result"')

        return JSON.parse(line)
      end
      nil
    rescue JSON::ParserError
      nil
    end
  end
end
