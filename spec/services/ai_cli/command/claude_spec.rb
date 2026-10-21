require "rails_helper"

RSpec.describe AiCli::Command::Claude do
  def build(**opts)
    described_class.new(prompt: "p", allowed_tools: nil, mcp_config: nil, disallowed_tools: [],
                        model: nil, effort: nil, verbose: false, **opts).to_a
  end

  it "skips permissions by default" do
    expect(build).to eq([ "claude", "-p", "p", "--dangerously-skip-permissions" ])
  end

  it "uses --allowedTools instead of the skip flag" do
    expect(build(allowed_tools: [ "Read", "Grep" ])).to eq([ "claude", "-p", "p", "--allowedTools", "Read", "Grep" ])
  end

  it "keeps flag ordering: mcp, disallowed, model, effort, stream-json" do
    cmd = build(mcp_config: "/tmp/m.json", disallowed_tools: [ "Bash" ], model: "opus", effort: "high", verbose: true)
    expect(cmd).to eq([ "claude", "-p", "p", "--dangerously-skip-permissions",
                        "--mcp-config", "/tmp/m.json", "--disallowedTools", "Bash",
                        "--model", "opus", "--effort", "high",
                        "--output-format", "stream-json", "--verbose", "--include-partial-messages" ])
  end
end
