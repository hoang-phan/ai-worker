module AiCli
  # Decides whether a detached agent run has finished and whether it succeeded.
  # Holds plain run state (no ActiveRecord); the caller persists #log_offset.
  class RunPoller
    attr_reader :log_offset

    def initialize(pid:, log_path:, log_offset:, started_at:, log_tag:, stale_after:, runner: AiCli::Runner, kill: Process.method(:kill), provider: nil)
      @pid = pid
      @provider = provider.presence
      @runner = runner
      @log_offset = log_offset
      @log_tail = AiCli::LogTail.new(log_path: log_path, log_tag: log_tag) if log_path
      @stale_after = stale_after
      @stale_run = AiCli::StaleRun.new(started_at: started_at, stale_after: stale_after, kill: kill)
    end

    # :running, or [:finished, output]. Raises AiCli::CommandError if the run failed or timed out.
    def call
      tail_log
      result = runner.poll(pid)

      if result == :running
        # Only a run that is still alive can be stale; checking first would
        # report a run that finished while no tick fired as timed out.
        if stale_run.stale?
          stale_run.terminate!(pid)
          raise AiCli::CommandError, "#{agent} timed out after #{stale_after.inspect} (pid=#{pid})"
        end
        return :running
      end

      _tag, exit_status = result
      tail_log
      output = AiCli::RunVerdict.new(
        exit_status: exit_status, output: full_log, agent: agent, pid: pid
      ).verify!

      [ :finished, output ]
    end

    private

    # The CLI this run started with: the provider recorded at launch, else the app-wide agent.
    def agent
      @provider || runner.agent
    end

    attr_reader :pid, :log_tail, :stale_after, :stale_run, :runner

    def tail_log
      return unless log_tail

      _content, @log_offset = log_tail.read_from(log_offset)
    end

    def full_log
      log_tail ? log_tail.full : ""
    end
  end
end
