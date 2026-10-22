require "rails_helper"

RSpec.describe Stages::RunProvider, type: :service do
  let(:store) { ActiveSupport::Cache::MemoryStore.new }
  let(:project) { build_jira_project }
  let(:workflow) { build_jira_workflow(project, jira_ticket: "RP-1", branch_name: "run-provider") }
  let(:agent) { nil }
  let(:stage) { instance_double(Stage, agent: agent) }

  subject(:run_provider) { described_class.new(workflow: workflow, stage: stage) }

  before do
    allow(Rails).to receive(:cache).and_return(store)
    AiCli::AgentSetting.current = "claude"
  end

  context "with a stage agent that names a provider" do
    let(:agent) { instance_double(Agent, provider: "codex") }

    it "wins over rotation and the app-wide setting" do
      AiCli::Rotation.weights = { "cursor" => 1 }

      expect(run_provider.override).to eq "codex"
      expect(run_provider.name).to eq "codex"
      expect(run_provider.provider).to eq AiCli::Providers.find("codex")
      expect(workflow.reload.rotation_provider).to be_nil
    end
  end

  context "with rotation enabled and an agent without a provider" do
    let(:agent) { instance_double(Agent, provider: "") }

    it "uses the workflow's pinned round-robin provider" do
      AiCli::Rotation.weights = { "cursor" => 1 }

      expect(run_provider.override).to eq "cursor"
      expect(run_provider.name).to eq "cursor"
      expect(workflow.reload.rotation_provider).to eq "cursor"
    end
  end

  context "with neither" do
    it "has no override and falls back to the app-wide agent" do
      AiCli::AgentSetting.current = "codex"

      expect(run_provider.override).to be_nil
      expect(run_provider.name).to eq "codex"
      expect(run_provider.provider).to eq AiCli::Providers.find("codex")
    end
  end
end
