require "rails_helper"

RSpec.describe AiCli::Command do
  def build(agent: "claude", prompt: "do it", **opts)
    described_class.new(agent: agent, prompt: prompt, verbose: false, **opts).to_a
  end

  describe "claude" do
    it "skips permissions by default" do
      expect(build).to eq([ "claude", "-p", "do it", "--dangerously-skip-permissions" ])
    end

    it "replaces the skip flag with --allowedTools" do
      cmd = build(allowed_tools: [ "Read", "Grep" ])
      expect(cmd).to eq([ "claude", "-p", "do it", "--allowedTools", "Read", "Grep" ])
      expect(cmd).not_to include("--dangerously-skip-permissions")
    end

    it "adds --mcp-config and --disallowedTools" do
      cmd = build(mcp_config: "/tmp/mcp.json", disallowed_tools: [ "Bash(gh workflow run:*)" ])
      expect(cmd).to include("--mcp-config", "/tmp/mcp.json", "--disallowedTools", "Bash(gh workflow run:*)")
    end

    it "adds stream-json flags when verbose" do
      cmd = described_class.new(agent: "claude", prompt: "p", verbose: true).to_a
      expect(cmd.last(4)).to eq([ "--output-format", "stream-json", "--verbose", "--include-partial-messages" ])
    end

    it "does not add stream-json flags for other agents" do
      cmd = described_class.new(agent: "codex", prompt: "p", verbose: true).to_a
      expect(cmd).not_to include("stream-json")
    end
  end

  describe "codex" do
    it "places mcp_servers overrides before the prompt" do
      dir = make_tmpdir("command-spec")
      path = File.join(dir, "mcp.json")
      File.write(path, JSON.generate(mcpServers: { "browser" => { "command" => "npx", "args" => [ "-y", "pw" ], "env" => { "A" => "1" } } }))
      cmd = build(agent: "codex", mcp_config: path)

      expect(cmd.first(2)).to eq([ "codex", "exec" ])
      expect(cmd.last(2)).to eq([ "--dangerously-bypass-approvals-and-sandbox", "do it" ])
      overrides = cmd[2...-2]
      expect(overrides.each_slice(2).map(&:first).uniq).to eq([ "-c" ])
      values = overrides.each_slice(2).map(&:last)
      expect(values).to include(
        'mcp_servers.browser.command="npx"',
        'mcp_servers.browser.args=["-y","pw"]',
        'mcp_servers.browser.env={"A" = "1"}',
        "mcp_servers.browser.startup_timeout_sec=90"
      )
    end
  end

  describe "cursor" do
    let(:mcp) { "/nonexistent/mcp.json" }

    def cursor(executables: [ "agent" ], help: "", **opts)
      described_class.new(agent: "cursor", prompt: "p", verbose: false,
                          executable_check: ->(name) { executables.include?(name) },
                          help_probe: ->(_binary) { help }, **opts).to_a
    end

    it "uses --force and the agent binary" do
      expect(cursor).to eq([ "agent", "-p", "p", "--force" ])
    end

    it "falls back to cursor-agent" do
      expect(cursor(executables: [ "cursor-agent" ]).first).to eq("cursor-agent")
    end

    it "adds --approve-mcps only when supported" do
      expect(cursor(mcp_config: mcp, help: "--approve-mcps  trust")).to end_with("--approve-mcps")
      expect(cursor(mcp_config: mcp, help: "nothing")).not_to include("--approve-mcps")
    end
  end

  it "raises CommandError for an unknown agent" do
    expect { build(agent: "bogus") }.to raise_error(AiCli::CommandError, /unknown AGENT/)
  end
end
