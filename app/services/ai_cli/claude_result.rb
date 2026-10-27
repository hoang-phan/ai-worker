module AiCli
  # Reads claude's stream-json log (the provider format, not the app's stage markers; see AiCli::Output).
  # Pure: no I/O, no workflow state.
  class ClaudeResult
    def initialize(text)
      @text = text.to_s
    end

    # The last valid `{"type":"result"}` event claude writes, or nil. Invalid JSON lines are skipped.
    def result_event
      text.each_line.reverse_each do |line|
        next unless line.start_with?("{")

        event = JSON.parse(line)
        return event if event.is_a?(Hash) && event["type"] == "result"
      rescue JSON::ParserError
        next
      end
      nil
    end

    # :success / :error from the last `{"type":"result"}` event claude writes,
    # nil if there is none (run killed mid-way, or another agent).
    def final_outcome
      event = result_event
      return unless event

      event["is_error"] ? :error : :success
    end

    private

    attr_reader :text
  end
end
