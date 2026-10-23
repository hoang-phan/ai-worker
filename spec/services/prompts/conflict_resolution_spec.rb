require "rails_helper"

RSpec.describe Prompts::ConflictResolution do
  it "tells the agent to resolve the merge without pushing" do
    expect(described_class::TEXT).to include("git merge main", "git commit --no-edit", "Do not push.")
  end

  it "is frozen" do
    expect(described_class::TEXT).to be_frozen
  end
end
