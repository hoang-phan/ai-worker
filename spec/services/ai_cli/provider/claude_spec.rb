require "rails_helper"

RSpec.describe AiCli::Provider::Claude do
  subject(:provider) { described_class.new }

  let(:success_event) { %({"type":"result","is_error":false,"result":"ok"}\n) }
  let(:error_event) { %({"type":"result","is_error":true,"result":"boom"}\n) }

  it "builds argv from the shared option set" do
    options = { prompt: "go", allowed_tools: [ "Read" ], mcp_config: nil, disallowed_tools: [], model: "m", effort: "high", verbose: false }

    expect(provider.builder(**options).to_a).to eq(%w[claude -p go --allowedTools Read --model m --effort high])
  end

  it "declares its capabilities" do
    expect(provider.capabilities).to eq(AiCli::Provider::Capabilities.new(tool_lists: true, model: true, effort: true, mcp: :flag))
  end

  it "leaves the command alone" do
    expect(provider.wrap(%w[x], project_directory: "/tmp", mcp_config: "/mcp.json")).to eq(%w[x])
  end

  it "reads its final result event" do
    expect(provider.outcome(success_event)).to eq(:success)
    expect(provider.outcome(error_event)).to eq(:error)
    expect(provider.outcome("no events")).to be_nil
  end
end
