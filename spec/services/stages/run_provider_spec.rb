require "rails_helper"

RSpec.describe Stages::RunProvider, type: :service do
  let(:project) { build_jira_project }
  let(:workflow) { build_jira_workflow(project, jira_ticket: "RP-1", branch_name: "run-provider") }

  subject(:run_provider) { described_class.new(workflow: workflow) }

  before { AiCli::AgentSetting.current = "claude" }

  context "with rotation enabled" do
    it "uses the workflow's pinned round-robin provider" do
      AiCli::Rotation.weights = { "cursor" => 1 }

      expect(run_provider.override).to eq "cursor"
      expect(workflow.reload.rotation_provider).to eq "cursor"
    end

    it "returns a previously pinned provider without advancing the rotation" do
      workflow.update!(rotation_provider: "claude")
      rotation = class_double(AiCli::Rotation)
      expect(rotation).not_to receive(:next_provider)

      expect(described_class.new(workflow: workflow, rotation: rotation).override).to eq "claude"
    end
  end

  context "with rotation off" do
    it "has no override, leaving the app-wide agent to the runner" do
      AiCli::AgentSetting.current = "codex"

      expect(run_provider.override).to be_nil
      expect(workflow.reload.rotation_provider).to be_nil
    end
  end
end
