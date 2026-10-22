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

  it "selects a model and configures reasoning effort" do
    cmd = described_class.new(prompt: "p", mcp_config: nil, model: "gpt-6-sol", effort: "high").to_a

    expect(cmd).to eq([ "codex", "exec",
                        "-c", 'model_reasoning_effort="high"',
                        "--dangerously-bypass-approvals-and-sandbox",
                        "--model", "gpt-6-sol", "p" ])
  end

  describe "MCP overrides" do
    let(:tail) { [ "--dangerously-bypass-approvals-and-sandbox", "p" ] }

    def argv(servers)
      described_class.new(prompt: "p", mcp_config: "/x.json", mcp_servers: ->(_path) { servers }).to_a
    end

    it "emits only command and the 90s startup timeout for a command-only server" do
      expect(argv("a" => { "command" => "run" })).to eq([ "codex", "exec",
                                                         "-c", 'mcp_servers.a.command="run"',
                                                         "-c", "mcp_servers.a.startup_timeout_sec=90",
                                                         *tail ])
    end

    it "adds args as a JSON array" do
      cmd = argv("a" => { "command" => "npx", "args" => [ "-y", "pkg@1" ] })

      expect(cmd).to include("-c", 'mcp_servers.a.args=["-y","pkg@1"]')
      expect(cmd).not_to include(a_string_matching(/\.env=/))
    end

    it "omits blank env" do
      expect(argv("a" => { "command" => "x", "env" => {} })).not_to include(a_string_matching(/\.env=/))
    end

    it "renders env as an inline table in order, escaping values" do
      env = { "A" => "1", "B" => 'say "hi"\\n', "C" => "x y" }
      cmd = argv("a" => { "command" => "x", "env" => env })

      expect(cmd).to include('mcp_servers.a.env={"A" = "1", "B" = "say \\"hi\\"\\\\n", "C" = "x y"}')
    end

    it "emits each server's flags in order" do
      cmd = argv("a" => { "command" => "one" }, "b" => { "command" => "two", "args" => [] })

      expect(cmd).to eq([ "codex", "exec",
                          "-c", 'mcp_servers.a.command="one"',
                          "-c", "mcp_servers.a.startup_timeout_sec=90",
                          "-c", 'mcp_servers.b.command="two"',
                          "-c", "mcp_servers.b.startup_timeout_sec=90",
                          "-c", "mcp_servers.b.args=[]",
                          *tail ])
    end

    it "emits nothing without mcp_config" do
      servers = ->(_path) { raise "should not be called" }

      expect(described_class.new(prompt: "p", mcp_config: "", mcp_servers: servers).to_a)
        .to eq([ "codex", "exec", *tail ])
    end
  end
end
