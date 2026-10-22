require "rails_helper"

RSpec.describe Prompts::StageSections::FixedSummary do
  def section(stage_type: "pr_check", notify_enabled: true)
    described_class.new(stage_type: stage_type, notify_enabled: notify_enabled).to_s
  end

  it "asks for a fixed summary on a pr_check run with notifications" do
    expect(section).to include("FIXED_SUMMARY_BEGIN", "FIXED_SUMMARY_END")
  end

  it "is empty for other stage types" do
    expect(section(stage_type: "implementation")).to eq("")
  end

  it "is empty when notifications are disabled" do
    expect(section(notify_enabled: false)).to eq("")
  end
end
