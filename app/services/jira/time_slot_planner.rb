module Jira
  # Picks when the next chunk of logged time goes: the first weekday (starting Monday of the current week)
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
      from = @today.beginning_of_week
      logs = TimeLog.where(started_at: from.in_time_zone..).to_a.group_by { |log| log.started_at.in_time_zone.to_date }
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

    def pick_time(date, seconds, logs)
      used = logs.map { |log| log.started_at.in_time_zone.strftime("%H:%M") }
      latest = [ DAY_END_HOUR - (seconds / 3600.0).ceil, DAY_START_HOUR ].max
      candidates = [ (DAY_START_HOUR..latest), (DAY_START_HOUR...DAY_END_HOUR) ].lazy.filter_map do |hours|
        free = hours.map { |h| format("%02d:00", h) } - used
        free.presence
      end.first
      candidates ||= (DAY_START_HOUR...DAY_END_HOUR).map { |h| format("%02d:30", h) } - used
      hhmm = candidates.presence&.sample(random: @random) || format("%02d:%02d", @random.rand(DAY_START_HOUR...DAY_END_HOUR), @random.rand(1..59))
      Time.zone.parse("#{date} #{hhmm}")
    end
  end
end
