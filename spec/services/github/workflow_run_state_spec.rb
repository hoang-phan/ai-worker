require "rails_helper"

RSpec.describe Github::WorkflowRunState do
  let(:since) { Time.zone.parse("2026-01-01T10:00:00Z") }

  def run(created_at, status:, conclusion: nil, url: "https://example.test/runs/#{created_at}")
    { "createdAt" => created_at, "status" => status, "conclusion" => conclusion, "url" => url }
  end

  it "ignores runs created before since" do
    runs = [ run("2026-01-01T09:59:59Z", status: "completed", conclusion: "success") ]

    expect(described_class.call(runs, since: since)).to eq(state: :none)
  end

  it "uses the newest eligible run" do
    runs = [
      run("2026-01-01T10:05:00Z", status: "completed", conclusion: "failure", url: "old"),
      run("2026-01-01T11:00:00Z", status: "completed", conclusion: "success", url: "new")
    ]

    expect(described_class.call(runs, since: since)).to eq(state: :success, url: "new", conclusion: "success")
  end

  it "returns pending with the run URL for queued and in-progress runs" do
    queued = run("2026-01-01T10:05:00Z", status: "queued", url: "queued")
    in_progress = run("2026-01-01T10:06:00Z", status: "in_progress", url: "in-progress")

    expect(described_class.call([ queued ], since: since)).to eq(state: :pending, url: "queued")
    expect(described_class.call([ in_progress ], since: since)).to eq(state: :pending, url: "in-progress")
  end

  it "maps completed success and failure runs with URL and conclusion" do
    success = run("2026-01-01T10:05:00Z", status: "completed", conclusion: "success", url: "success")
    failure = run("2026-01-01T10:05:00Z", status: "completed", conclusion: "failure", url: "failure")

    expect(described_class.call([ success ], since: since)).to eq(state: :success, url: "success", conclusion: "success")
    expect(described_class.call([ failure ], since: since)).to eq(state: :failed, url: "failure", conclusion: "failure")
  end

  it "returns none when there are no runs" do
    expect(described_class.call([], since: since)).to eq(state: :none)
  end
end
