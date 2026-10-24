require "rails_helper"

RSpec.describe AiCli::Provider do
  subject(:provider) { described_class.new(name: "x", capabilities: capabilities) }

  let(:capabilities) { described_class::Capabilities.new(tool_lists: true, model: true, effort: true, mcp: :flag) }

  describe "#builder" do
    it "must be implemented by a provider" do
      expect { provider.builder(prompt: "go") }.to raise_error(NotImplementedError)
    end
  end

  describe "#wrap" do
    it "leaves the command alone" do
      expect(provider.wrap(%w[x], project_directory: "/tmp", mcp_config: "/mcp.json")).to eq(%w[x])
    end
  end

  describe "#outcome" do
    it "is unknown" do
      expect(provider.outcome("output")).to be_nil
    end
  end

  describe "Capabilities" do
    it "records provider support" do
      expect(capabilities).to have_attributes(tool_lists: true, model: true, effort: true, mcp: :flag)
    end
  end
end
