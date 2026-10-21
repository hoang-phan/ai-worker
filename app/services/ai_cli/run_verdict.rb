module AiCli
  # Pure decision on a finished detached run: given its exit status (nil when
  # the process was reaped elsewhere) and full log output, return the output
  # or raise AiCli::CommandError. No file or process I/O.
  class RunVerdict
    def initialize(exit_status:, output:, agent:, pid:)
      @exit_status = exit_status
      @output = output
      @agent = agent
      @pid = pid
    end

    def verify!
      raise failed unless exit_status.nil? || exit_status.success?

      # No status when the process was reaped elsewhere (e.g. Sidekiq restarted
      # mid-run); claude's final result event in the log says how it ended.
      if exit_status.nil?
        outcome = AiCli::Output.new(output).final_outcome
        raise AiCli::CommandError, "#{agent} exit status unknown (pid=#{pid}), treating as failed" if outcome.nil?
        raise failed if outcome == :error
      end

      output
    end

    private

    attr_reader :exit_status, :output, :agent, :pid

    def failed
      AiCli::CommandError.new("#{agent} failed (pid=#{pid}): #{output.presence || 'no output'}")
    end
  end
end
