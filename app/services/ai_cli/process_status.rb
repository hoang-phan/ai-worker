module AiCli
  # Non-blocking status of a spawned agent process: returns :running, or
  # [:completed, Process::Status-or-nil]. `process` is injectable so the
  # wait2/getpgid/ECHILD/ESRCH handling can be tested without real processes.
  class ProcessStatus
    def initialize(process: Process)
      @process = process
    end

    def call(pid)
      _reaped_pid, status = @process.wait2(pid, Process::WNOHANG)
      status ? [ :completed, status ] : :running
    rescue Errno::ECHILD
      # Not our child anymore (e.g. the Sidekiq process restarted mid-run).
      # Fall back to a liveness check since we can no longer reap it.
      begin
        @process.getpgid(pid)
        :running
      rescue Errno::ESRCH
        [ :completed, nil ]
      end
    rescue Errno::ESRCH
      [ :completed, nil ]
    end
  end
end
