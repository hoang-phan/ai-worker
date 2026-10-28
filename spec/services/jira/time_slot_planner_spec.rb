require "rails_helper"

RSpec.describe Jira::TimeSlotPlanner do
  let(:slot_log_class) { Struct.new(:started_at, :seconds) }
  let(:monday) { Date.new(2027, 2, 1) } # the 1st of the month, a Monday
  let(:logs) { [] }
  let(:planner) { described_class.new(today: monday + 2, logs: ->(_from) { logs }) }

  def log(date, hours, hour: 6)
    logs << slot_log_class.new(Time.zone.local(date.year, date.month, date.day, hour), (hours * 3600).to_i)
  end

  def place(hours)
    start = planner.next_start((hours * 3600).to_i)
    logs << slot_log_class.new(start, (hours * 3600).to_i)
    start
  end

  it "fills the first non-full weekday, whole entries at a time" do
    log(monday, 7)
    log(monday + 1, 5)
    log(monday + 2, 2)

    days = [ 1.5, 1, 3, 1, 2 ].map { |hours| place(hours).to_date }

    expect(days).to eq([ monday + 1, monday + 2, monday + 2, monday + 3, monday + 3 ])
  end

  it "starts from the first available day of the month, not the current week" do
    planner = described_class.new(today: Date.new(2026, 10, 22), logs: ->(_from) { logs })

    expect(planner.next_start(3600).to_date).to eq(Date.new(2026, 10, 1))
  end

  it "skips weekends" do
    (0..4).each { |offset| log(monday + offset, 6) }

    expect(place(1).to_date).to eq(monday + 7)
  end

  it "uses a start hour between 6AM and 5PM that is not already used that day" do
    starts = Array.new(6) { place(0.5) }

    expect(starts.map(&:hour).uniq.size).to eq(6)
    expect(starts).to all(satisfy { |t| t.hour >= 6 && t.hour < 17 && t.to_date == monday })
  end

  it "keeps a long duration at or before the last whole hour that leaves room for it" do
    # 8h => latest start is 17 - 8 = 9, so only 06:00..09:00 qualify
    log(monday, 0.5, hour: 6)
    log(monday, 0.5, hour: 7)

    starts = Array.new(20) { planner.next_start(8 * 3600) }

    expect(starts.map { |t| t.strftime("%H:%M") }).to all(satisfy { |hhmm| %w[08:00 09:00].include?(hhmm) })
  end

  it "falls back to any free whole hour when the long-duration slots are all used" do
    (6..9).each { |hour| log(monday, 0.5, hour: hour) }

    starts = Array.new(20) { planner.next_start(8 * 3600) }

    expect(starts.map(&:hour)).to all(satisfy { |hour| (10...17).cover?(hour) })
    expect(starts).to all(satisfy { |t| t.min.zero? })
  end

  it "falls back to a half hour when every whole hour of the day is used" do
    (6...17).each { |hour| log(monday, 0.25, hour: hour) }

    start = planner.next_start(3600)

    expect(start.to_date).to eq(monday)
    expect(start.min).to eq(30)
    expect(start.hour).to be_between(6, 16)
  end

  it "uses a seeded random HH:MM when every :00 and :30 is used" do
    (6...17).each do |hour|
      log(monday, 0.1, hour: hour)
      logs << slot_log_class.new(Time.zone.local(2027, 2, 1, hour, 30), 360)
    end
    expected = Random.new(42).then { |r| format("%02d:%02d", r.rand(6...17), r.rand(1..59)) }
    planner = described_class.new(today: monday + 2, random: Random.new(42), logs: ->(_from) { logs })

    start = planner.next_start(3600)

    expect(start.to_date).to eq(monday)
    expect(start.strftime("%H:%M")).to eq(expected)
    expect(start.min).to be_between(1, 59)
  end

  it "uses the default source to read persisted time logs" do
    project = build_jira_project
    workflow = build_jira_workflow(project)
    workflow.time_logs.create!(ticket_key: "PLAN-1", started_at: Time.zone.local(2027, 2, 1, 6), seconds: 7 * 3600)

    start = described_class.new(today: monday + 2).next_start(3600)

    expect(start.to_date).to eq(monday + 1)
  end
end
