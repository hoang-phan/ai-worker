require "rails_helper"

RSpec.describe Prompts::StageSections::LessonsRequest do
  it "asks a pr_check run for lessons between the markers" do
    expect(described_class.new(stage_type: "pr_check").to_s).to include("LESSONS_BEGIN", "LESSONS_END", "0-3")
  end

  it "is empty for other stage types" do
    expect(described_class.new(stage_type: "implementation").to_s).to eq("")
  end
end
