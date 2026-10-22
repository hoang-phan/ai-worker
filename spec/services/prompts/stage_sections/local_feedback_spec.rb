require "rails_helper"

RSpec.describe Prompts::StageSections::LocalFeedback do
  def section(stage_type: "pr_check", local_test_ready: true, feedback: nil)
    described_class.new(stage_type: stage_type, local_test_ready: local_test_ready, feedback: feedback).to_s
  end

  it "only asks the retest question when there is no feedback" do
    expect(section).to start_with("\nThis project is also tested locally").and include("LOCAL_RETEST: YES")
  end

  it "includes the findings as data when there is feedback" do
    expect(section(feedback: "button broken")).to include("<local_test_feedback>\nbutton broken\n</local_test_feedback>", "LOCAL_RETEST: NO")
  end

  it "treats blank feedback as none" do
    expect(section(feedback: " ")).not_to include("local_test_feedback")
  end

  it "is empty for other stage types" do
    expect(section(stage_type: "implementation")).to eq("")
  end

  it "is empty when the project is not ready for local tests" do
    expect(section(local_test_ready: false)).to eq("")
  end
end
