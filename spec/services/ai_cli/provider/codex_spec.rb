require "rails_helper"

RSpec.describe AiCli::Provider::Codex do
  subject(:provider) { described_class.new }

  let(:success_event) { %({"type":"result","is_error":false,"result":"ok"}\n) }

  it "builds argv from the shared option set" do
    options = { prompt: "go", allowed_tools: [ "Read" ], mcp_config: nil, disallowed_tools: [], model: "m", effort: "high", verbose: false }

    expect(provider.builder(**options).to_a)
      .to eq([ "codex", "exec", "-c", 'model_reasoning_effort="high"', "--dangerously-bypass-approvals-and-sandbox", "--model", "m", "go" ])
  end

  it "declares its capabilities" do
    expect(provider.capabilities).to eq(AiCli::Provider::Capabilities.new(tool_lists: false, model: true, effort: true, mcp: :overrides))
  end

  it "leaves the command alone" do
    expect(provider.wrap(%w[x], project_directory: "/tmp", mcp_config: "/mcp.json")).to eq(%w[x])
  end

  it "has no result event outcome" do
    expect(provider.outcome(success_event)).to be_nil
  end
end
