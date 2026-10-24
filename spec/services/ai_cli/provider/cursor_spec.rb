require "rails_helper"

RSpec.describe AiCli::Provider::Cursor do
  subject(:provider) { described_class.new }

  let(:success_event) { %({"type":"result","is_error":false,"result":"ok"}\n) }

  it "builds argv from the shared option set" do
    options = { prompt: "go", allowed_tools: [ "Read" ], mcp_config: nil, disallowed_tools: [], model: "m", effort: "high", verbose: false }

    expect(provider.builder(**options, executable_check: ->(name) { name == "agent" }).to_a).to eq(%w[agent -p go --force])
  end

  it "declares its capabilities" do
    expect(provider.capabilities).to eq(AiCli::Provider::Capabilities.new(tool_lists: false, model: false, effort: false, mcp: :file))
  end

  it "writes its MCP file around the run only when an MCP config is given" do
    file = instance_double(AiCli::CursorMcpFile)
    allow(AiCli::CursorMcpFile).to receive(:new).with("/tmp", "/mcp.json").and_return(file)
    allow(file).to receive(:wrap).with(%w[x]).and_return(%w[wrapped])

    expect(provider.wrap(%w[x], project_directory: "/tmp", mcp_config: "/mcp.json")).to eq(%w[wrapped])
    expect(provider.wrap(%w[x], project_directory: "/tmp", mcp_config: nil)).to eq(%w[x])
  end

  it "has no result event outcome" do
    expect(provider.outcome(success_event)).to be_nil
  end
end
