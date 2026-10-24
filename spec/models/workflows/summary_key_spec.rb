require "rails_helper"

RSpec.describe Workflows::SummaryKey do
  it "downcases, turns non-alphanumerics into single spaces and strips" do
    expect(described_class.call("  Fix: the BUG!! (again) ")).to eq "fix the bug again"
  end

  it "treats differently punctuated text as the same key" do
    expect(described_class.call("fix a!")).to eq described_class.call("Fix  A")
  end

  it "returns an empty string for nil" do
    expect(described_class.call(nil)).to eq ""
  end

  describe ".set" do
    it "returns the set of normalized briefs of the given workflows" do
      workflows = [ Struct.new(:brief).new("Fix: A!"), Struct.new(:brief).new("fix a"), Struct.new(:brief).new("Other") ]

      expect(described_class.set(workflows)).to eq Set["fix a", "other"]
    end

    it "is empty for no workflows" do
      expect(described_class.set([])).to eq Set.new
    end
  end
end
