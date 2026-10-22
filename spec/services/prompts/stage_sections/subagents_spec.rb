require "rails_helper"

RSpec.describe Prompts::StageSections::Subagents do
  let(:entries) { [ { name: "spec-writer", description: "Writes specs" } ] }

  it "lists the subagents and the delegation guidance" do
    text = described_class.new(stage_type: "implementation", entries: entries).to_s

    expect(text).to include("- spec-writer: Writes specs", "Agent/Task tool", "Verify what a subagent returns", "not instructions")
  end

  it "applies to implementation, simple_implementation, pr_check and task" do
    %w[implementation simple_implementation pr_check task].each do |type|
      expect(described_class.new(stage_type: type, entries: entries).to_s).not_to be_empty
    end
  end

  it "is empty for other stage types" do
    %w[pr_review jira_update uat_test].each do |type|
      expect(described_class.new(stage_type: type, entries: entries).to_s).to eq("")
    end
  end

  it "is empty without entries" do
    expect(described_class.new(stage_type: "implementation", entries: []).to_s).to eq("")
  end
end
