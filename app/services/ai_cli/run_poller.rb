module AiCli
  # Decides whether a detached agent run has finished and whether it succeeded.
  # Holds plain run state (no ActiveRecord); the caller persists #log_offset.
  class RunPoller
    attr_reader :log_offset

    def initialize(pid:, log_path:, log_offset:, started_at:, log_tag:, stale_after:)
      @pid = pid
      @log_offset = log_offset
      @started_at = started_at
      @log_tail = AiCli::LogTail.new(log_path: log_path, log_tag: log_tag) if log_path
      @stale_after = stale_after
    end

    # :running, or [:finished, output]. Raises AiCli::CommandError if the run failed or timed out.
    def call
      tail_log
      result = AiCli::Runner.poll(pid)

      if result == :running
        # Only a run that is still alive can be stale; checking first would
        # report a run that finished while no tick fired as timed out.
        if stale?
          kill_stale_run
          raise AiCli::CommandError, "#{AiCli::Runner.agent} timed out after #{stale_after.inspect} (pid=#{pid})"
        end
        return :running
      end

      _tag, exit_status = result
      tail_log
      output = full_log

      unless exit_status.nil? || exit_status.success?
        raise AiCli::CommandError, "#{AiCli::Runner.agent} failed (pid=#{pid}): #{output.presence || 'no output'}"
      end
      # No status when the process was reaped elsewhere (e.g. Sidekiq restarted
      # mid-run); claude's final result event in the log says how it ended.
      if exit_status.nil?
        outcome = AiCli::Output.new(output).final_outcome
        raise AiCli::CommandError, "#{AiCli::Runner.agent} exit status unknown (pid=#{pid}), treating as failed" if outcome.nil?
        raise AiCli::CommandError, "#{AiCli::Runner.agent} failed (pid=#{pid}): #{output.presence || 'no output'}" if outcome == :error
      end

      [ :finished, output ]
    end

    private

    attr_reader :pid, :log_tail, :started_at, :stale_after

    def tail_log
      return unless log_tail

      _content, @log_offset = log_tail.read_from(log_offset)
    end

    def full_log
      log_tail ? log_tail.full : ""
    end

    def stale?
      started_at.present? && started_at < stale_after.ago
    end

    def kill_stale_run
      Process.kill("TERM", pid)
    rescue Errno::ESRCH
      nil
    end
  end
end
