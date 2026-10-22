require "rails_helper"

RSpec.describe Prompts::StageSections::Retry do
  def section(stage_type: "implementation", last_action: "failed", previous_log: "/tmp/run.log")
    described_class.new(stage_type: stage_type, last_action: last_action, previous_log: previous_log).to_s
  end

  it "points at the previous log after a failed implementation run" do
    expect(section).to include("A previous attempt at this stage ended without finishing", "/tmp/run.log")
  end

  it "is empty unless the stage is an implementation" do
    expect(section(stage_type: "pr_check")).to eq("")
  end

  it "is empty unless the last run failed" do
    expect(section(last_action: "completed")).to eq("")
  end

  it "is empty without a previous log" do
    expect(section(previous_log: nil)).to eq("")
  end
end
