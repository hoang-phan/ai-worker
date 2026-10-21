module AgentRuns
  # Pure "is it time to start another run?" rules for SyncCycle's `due:` callback.
  module Cadence
    module_function

    # Due when never started, or the last start is at least `interval` old (boundary inclusive).
    def every(interval, last_started_at:, now: Time.current)
      last_started_at.nil? || last_started_at <= now - interval
    end

    # Due on weekdays at/after `hour` (app time zone) when no run has started yet today.
    def daily_on_weekdays(hour:, last_started_at:, now: Time.zone.now)
      return false if now.saturday? || now.sunday? || now.hour < hour

      last_started_at.nil? || last_started_at < now.beginning_of_day
    end
  end
end
