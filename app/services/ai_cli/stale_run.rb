module AiCli
  # A detached run that has been going longer than its allowed time. A missing started_at is never stale here
  # (AiCli::DetachedRun treats it the other way on purpose). Holds plain state; the caller picks the signal target
  # (a pid, or -pid for a process group).
  class StaleRun
    def initialize(started_at:, stale_after:, kill: Process.method(:kill), clock: -> { Time.current })
      @started_at = started_at
      @stale_after = stale_after
      @kill = kill
      @clock = clock
    end

    def stale?
      started_at.present? && started_at < stale_after.before(clock.call)
    end

    # Sends TERM to target; a process that is already gone is fine.
    def terminate!(target)
      kill.call("TERM", target)
    rescue Errno::ESRCH
      nil
    end

    private

    attr_reader :started_at, :stale_after, :kill, :clock
  end
end
