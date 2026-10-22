require "rails_helper"

RSpec.describe Github::FailingChecks do
  it "is true for a failing conclusion" do
    rollup = [ { "conclusion" => "SUCCESS" }, { "conclusion" => "TIMED_OUT" } ]

    expect(described_class.call(rollup)).to be(true)
  end

  it "is true for a failing state" do
    expect(described_class.call([ { "state" => "ERROR" } ])).to be(true)
  end

  it "ignores queued and in-progress checks with no conclusion" do
    rollup = [
      { "status" => "QUEUED", "conclusion" => "" },
      { "status" => "IN_PROGRESS", "conclusion" => nil },
      { "conclusion" => "SUCCESS" }
    ]

    expect(described_class.call(rollup)).to be(false)
  end

  it "matches lowercase values" do
    expect(described_class.call([ { "conclusion" => "failure" } ])).to be(true)
    expect(described_class.call([ { "state" => "error" } ])).to be(true)
  end

  it "is false for an empty rollup" do
    expect(described_class.call([])).to be(false)
  end
end
