module Ci
  # The ci_check twin of AiCli::RunPoller: a CI command that exits non-zero is a normal result (the verify stage reads
  # the failure), so only a timeout or an unknown exit status raises.
  class CheckPoller
    attr_reader :log_offset

    def initialize(pid:, log_offset:, started_at:, stale_after:, **)
      @pid = pid
      @log_offset = log_offset
      @started_at = started_at
      @stale_after = stale_after
    end

    # :running, or [:finished, exit_status]. Raises AiCli::CommandError on a timeout or when the status is unknown.
    def call
      result = AiCli::Runner.poll(pid)

      if result == :running
        return :running unless stale?

        kill_stale_run
        raise AiCli::CommandError, "CI command timed out after #{stale_after.inspect} (pid=#{pid})"
      end

      _tag, status = result
      raise AiCli::CommandError, "CI command exit status unknown (pid=#{pid}), running it again" if status.nil?

      [ :finished, status.success? ? 0 : (status.exitstatus || 1) ]
    end

    private

    attr_reader :pid, :started_at, :stale_after

    def stale?
      started_at.present? && started_at < stale_after.ago
    end

    def kill_stale_run
      Process.kill("TERM", -pid)
    rescue Errno::ESRCH
      nil
    end
  end
end
