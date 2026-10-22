module AiCli
  # Decides whether a detached agent run has finished and whether it succeeded.
  # Holds plain run state (no ActiveRecord); the caller persists #log_offset.
  class RunPoller
    attr_reader :log_offset

    def initialize(pid:, log_path:, log_offset:, started_at:, log_tag:, stale_after:, runner: AiCli::Runner, kill: Process.method(:kill))
      @pid = pid
      @runner = runner
      @kill = kill
      @log_offset = log_offset
      @started_at = started_at
      @log_tail = AiCli::LogTail.new(log_path: log_path, log_tag: log_tag) if log_path
      @stale_after = stale_after
    end

    # :running, or [:finished, output]. Raises AiCli::CommandError if the run failed or timed out.
    def call
      tail_log
      result = runner.poll(pid)

      if result == :running
        # Only a run that is still alive can be stale; checking first would
        # report a run that finished while no tick fired as timed out.
        if stale?
          kill_stale_run
          raise AiCli::CommandError, "#{runner.agent} timed out after #{stale_after.inspect} (pid=#{pid})"
        end
        return :running
      end

      _tag, exit_status = result
      tail_log
      output = AiCli::RunVerdict.new(
        exit_status: exit_status, output: full_log, agent: runner.agent, pid: pid
      ).verify!

      [ :finished, output ]
    end

    private

    attr_reader :pid, :log_tail, :started_at, :stale_after, :runner, :kill

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
      kill.call("TERM", pid)
    rescue Errno::ESRCH
      nil
    end
  end
end
