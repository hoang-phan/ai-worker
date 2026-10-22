require "rails_helper"

RSpec.describe AiCli::Provider do
  let(:success_event) { %({"type":"result","is_error":false,"result":"ok"}\n) }
  let(:error_event) { %({"type":"result","is_error":true,"result":"boom"}\n) }

  describe "#builder" do
    it "builds each provider's argv from the shared option set, ignoring options it has no flag for" do
      options = { prompt: "go", allowed_tools: [ "Read" ], mcp_config: nil, disallowed_tools: [], model: "m", effort: "high", verbose: false }

      expect(AiCli::Providers.fetch("claude").builder(**options).to_a).to eq(%w[claude -p go --allowedTools Read --model m --effort high])
      expect(AiCli::Providers.fetch("codex").builder(**options).to_a)
        .to eq([ "codex", "exec", "-c", 'model_reasoning_effort="high"', "--dangerously-bypass-approvals-and-sandbox", "--model", "m", "go" ])
      expect(AiCli::Providers.fetch("cursor").builder(**options, executable_check: ->(name) { name == "agent" }).to_a).to eq(%w[agent -p go --force])
    end

    it "must be implemented by a provider" do
      provider = described_class.new(name: "x", capabilities: nil)

      expect { provider.builder(prompt: "go") }.to raise_error(NotImplementedError)
    end
  end

  describe "#wrap" do
    it "leaves the command alone for providers without run setup" do
      %w[claude codex].each do |name|
        expect(AiCli::Providers.fetch(name).wrap(%w[x], project_directory: "/tmp", mcp_config: "/mcp.json")).to eq(%w[x])
      end
    end

    it "has cursor write its MCP file around the run, only when an MCP config is given" do
      cursor = AiCli::Providers.fetch("cursor")
      file = instance_double(AiCli::CursorMcpFile)
      allow(AiCli::CursorMcpFile).to receive(:new).with("/tmp", "/mcp.json").and_return(file)
      allow(file).to receive(:wrap).with(%w[x]).and_return(%w[wrapped])

      expect(cursor.wrap(%w[x], project_directory: "/tmp", mcp_config: "/mcp.json")).to eq(%w[wrapped])
      expect(cursor.wrap(%w[x], project_directory: "/tmp", mcp_config: nil)).to eq(%w[x])
    end
  end

  describe "#outcome" do
    it "reads claude's final result event" do
      claude = AiCli::Providers.fetch("claude")

      expect(claude.outcome(success_event)).to eq(:success)
      expect(claude.outcome(error_event)).to eq(:error)
      expect(claude.outcome("no events")).to be_nil
    end

    it "is unknown for providers whose logs carry no result event" do
      %w[codex cursor].each { |name| expect(AiCli::Providers.fetch(name).outcome(success_event)).to be_nil }
    end
  end
end
