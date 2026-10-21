require "rails_helper"

RSpec.describe AiCli::Command::Cursor do
  def build(executables: [ "agent" ], help: "", mcp_config: nil)
    described_class.new(prompt: "p", mcp_config: mcp_config,
                        executable_check: ->(name) { executables.include?(name) },
                        help_probe: ->(_binary) { help }).to_a
  end

  it "uses the agent binary with --force" do
    expect(build).to eq([ "agent", "-p", "p", "--force" ])
  end

  it "falls back to cursor-agent, then to agent when neither exists" do
    expect(build(executables: [ "cursor-agent" ]).first).to eq("cursor-agent")
    expect(build(executables: []).first).to eq("agent")
  end

  it "adds --approve-mcps only with an MCP config and support in --help" do
    expect(build(mcp_config: "/m.json", help: "--approve-mcps")).to end_with("--approve-mcps")
    expect(build(mcp_config: "/m.json", help: "")).not_to include("--approve-mcps")
    expect(build(help: "--approve-mcps")).not_to include("--approve-mcps")
  end

  it "probes the resolved binary" do
    probed = nil
    described_class.new(prompt: "p", mcp_config: "/m.json", executable_check: ->(n) { n == "cursor-agent" },
                        help_probe: ->(b) { probed = b; "" }).to_a
    expect(probed).to eq("cursor-agent")
  end
end
