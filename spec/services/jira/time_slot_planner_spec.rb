require "rails_helper"

RSpec.describe Jira::TimeSlotPlanner do
  let(:project) { Project.create!(name: "Planner spec", kind: :jira, repo_full_name: "org/repo", local_directory: "/tmp") }
  let(:workflow) { project.workflows.create!(jira_ticket: "PLAN-1", branch_name: "plan-1", github_reviewer: "x") }
  let(:monday) { Date.new(2027, 2, 1) } # the 1st of the month, a Monday
  let(:planner) { described_class.new(today: monday + 2) }

  def log(date, hours, hour: 6)
    workflow.time_logs.create!(ticket_key: "PLAN-1", started_at: Time.zone.local(date.year, date.month, date.day, hour), seconds: (hours * 3600).to_i)
  end

  def place(hours)
    start = planner.next_start((hours * 3600).to_i)
    log(start.to_date, hours, hour: start.hour)
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
    planner = described_class.new(today: Date.new(2026, 10, 22))

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
end
