require "rails_helper"

RSpec.describe Stages::RunProvider, type: :service do
  let(:store) { ActiveSupport::Cache::MemoryStore.new }
  let(:project) { build_jira_project }
  let(:workflow) { build_jira_workflow(project, jira_ticket: "RP-1", branch_name: "run-provider") }
  let(:stage) { instance_double(Stage) }

  subject(:run_provider) { described_class.new(workflow: workflow, stage: stage) }

  before do
    allow(Rails).to receive(:cache).and_return(store)
    AiCli::AgentSetting.current = "claude"
  end

  context "with rotation enabled" do
    it "uses the workflow's pinned round-robin provider" do
      AiCli::Rotation.weights = { "cursor" => 1 }

      expect(run_provider.override).to eq "cursor"
      expect(run_provider.name).to eq "cursor"
      expect(workflow.reload.rotation_provider).to eq "cursor"
    end
  end

  context "with rotation off" do
    it "has no override and falls back to the app-wide agent" do
      AiCli::AgentSetting.current = "codex"

      expect(run_provider.override).to be_nil
      expect(run_provider.name).to eq "codex"
      expect(run_provider.provider).to eq AiCli::Providers.find("codex")
    end
  end
end
