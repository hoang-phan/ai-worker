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
end
