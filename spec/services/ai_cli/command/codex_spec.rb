require "rails_helper"

RSpec.describe AiCli::Command::Codex do
  it "builds a plain exec command without MCP config" do
    expect(described_class.new(prompt: "p", mcp_config: nil).to_a)
      .to eq([ "codex", "exec", "--dangerously-bypass-approvals-and-sandbox", "p" ])
  end

  it "emits TOML overrides from injected servers between exec and the flags" do
    servers = ->(_path) { { "b" => { "command" => "npx", "args" => [ "-y" ], "env" => { "A" => "1" } } } }
    cmd = described_class.new(prompt: "p", mcp_config: "/x.json", mcp_servers: servers).to_a
    expect(cmd).to eq([ "codex", "exec",
                        "-c", 'mcp_servers.b.command="npx"',
                        "-c", "mcp_servers.b.startup_timeout_sec=90",
                        "-c", 'mcp_servers.b.args=["-y"]',
                        "-c", 'mcp_servers.b.env={"A" = "1"}',
                        "--dangerously-bypass-approvals-and-sandbox", "p" ])
  end
end
