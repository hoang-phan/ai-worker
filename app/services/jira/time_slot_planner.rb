module Jira
  # Picks when the next chunk of logged time goes: the first weekday (starting on the 1st of the current month, so gaps earlier in the month are filled first)
  # whose global total is still under DAILY_TARGET, at a random whole hour between 6AM and 5PM that no
  # existing log that day already starts at (overlapping other entries is fine).
  class TimeSlotPlanner
    DAILY_TARGET = 6 * 3600
    DAY_START_HOUR = 6
    DAY_END_HOUR = 17

    def initialize(today: Time.zone.today, random: Random)
      @today = today
      @random = random
    end

    # Returns the Time the worklog should start at.
    def next_start(seconds)
      from = @today.beginning_of_month
      logs = logs_by_date(from)
      date = from
      date += 1 while weekend?(date) || total(logs[date]) >= DAILY_TARGET
      pick_time(date, seconds, logs[date] || [])
    end

    private

    def weekend?(date)
      date.saturday? || date.sunday?
    end

    def total(logs)
      Array(logs).sum(&:seconds)
    end

    def logs_by_date(from)
      TimeLog.where(started_at: from.in_time_zone..).to_a.group_by { |log| log.started_at.in_time_zone.to_date }
    end

    def pick_time(date, seconds, logs)
      slots = free_slots(seconds, used_times(logs))
      hhmm = slots&.sample(random: @random) || random_time
      Time.zone.parse("#{date} #{hhmm}")
    end

    def used_times(logs)
      logs.map { |log| log.started_at.in_time_zone.strftime("%H:%M") }
    end

    # First non-empty candidate list, tried in order: whole hours leaving room for the duration,
    # any whole hour, any half hour. Nil when every slot is taken.
    def free_slots(seconds, used)
      latest = [ DAY_END_HOUR - (seconds / 3600.0).ceil, DAY_START_HOUR ].max
      [ whole_hour_slots(latest), whole_hour_slots(DAY_END_HOUR - 1), half_hour_slots ]
        .lazy.map { |slots| slots - used }.find(&:present?)
    end

    def whole_hour_slots(latest_hour)
      (DAY_START_HOUR..latest_hour).map { |h| format("%02d:00", h) }
    end

    def half_hour_slots
      (DAY_START_HOUR...DAY_END_HOUR).map { |h| format("%02d:30", h) }
    end

    def random_time
      format("%02d:%02d", @random.rand(DAY_START_HOUR...DAY_END_HOUR), @random.rand(1..59))
    end
  end
end
