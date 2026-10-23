require "rails_helper"

RSpec.describe Github::FailingChecks do
  Github::FailingChecks::FAILED_CONCLUSIONS.each do |conclusion|
    it "is true for failing conclusion #{conclusion}" do
      expect(described_class.call([ { "conclusion" => conclusion.downcase } ])).to be(true)
    end
  end

  Github::FailingChecks::FAILED_STATES.each do |state|
    it "is true for failing state #{state}" do
      expect(described_class.call([ { "state" => state.downcase } ])).to be(true)
    end
  end

  it "ignores queued and in-progress checks with no conclusion" do
    rollup = [
      { "status" => "QUEUED", "conclusion" => "" },
      { "status" => "IN_PROGRESS", "conclusion" => nil },
      { "state" => "PENDING" },
      { "conclusion" => "SUCCESS" }
    ]

    expect(described_class.call(rollup)).to be(false)
  end

  it "is false for an empty rollup" do
    expect(described_class.call([])).to be(false)
  end
end
