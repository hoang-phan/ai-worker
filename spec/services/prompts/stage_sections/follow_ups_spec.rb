require "rails_helper"

RSpec.describe Prompts::StageSections::FollowUps do
  it "asks task runs for at most 2 follow-ups between the markers" do
    expect(described_class.new(stage_type: "task").to_s).to include("FOLLOW_UPS_BEGIN", "FOLLOW_UPS_END", "at most 2", "Omit the block")
  end

  it "is empty for other stage types" do
    %w[implementation simple_implementation pr_check].each do |type|
      expect(described_class.new(stage_type: type).to_s).to eq("")
    end
  end
end
