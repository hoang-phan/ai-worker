require "rails_helper"

RSpec.describe AiCli::Provider::Cursor do
  subject(:provider) { described_class.new }

  let(:success_event) { %({"type":"result","is_error":false,"result":"ok"}\n) }
  let_tmpdir(:directory, "cursor-provider-spec")
  let(:mcp_config) do
    File.join(directory, "mcp-config.json").tap do |path|
      File.write(path, JSON.generate(mcpServers: { "browser" => { "command" => "npx" } }))
    end
  end

  it "builds argv from the shared option set" do
    options = { prompt: "go", allowed_tools: [ "Read" ], mcp_config: nil, disallowed_tools: [], model: "m", effort: "high", verbose: false }

    expect(provider.builder(**options, executable_check: ->(name) { name == "agent" }).to_a).to eq(%w[agent -p go --force])
  end

  it "declares its capabilities" do
    expect(provider.capabilities).to eq(AiCli::Provider::Capabilities.new(tool_lists: false, model: false, effort: false, mcp: :file))
  end

  it "writes its MCP file around the run only when an MCP config is given" do
    mcp_file = File.join(directory, ".cursor", "mcp.json")

    result = provider.wrap(%w[x], project_directory: directory, mcp_config: mcp_config)

    expect(result.first(4)).to eq([ "sh", "-c", AiCli::CursorMcpFile::RESTORE_SCRIPT, mcp_file ])
    expect(result).to end_with("x")
    expect(File).to exist(mcp_file)
    expect(provider.wrap(%w[x], project_directory: directory, mcp_config: nil)).to eq(%w[x])
  end

  it "has no result event outcome" do
    expect(provider.outcome(success_event)).to be_nil
  end
end
