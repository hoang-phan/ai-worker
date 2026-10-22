require "rails_helper"

RSpec.describe AiCli::Providers do
  it "lists the supported agent CLIs in display order" do
    expect(described_class.names).to eq(%w[claude cursor codex])
  end

  it "finds providers by name, string or symbol" do
    expect(described_class.find("codex")).to be_a(AiCli::Provider::Codex)
    expect(described_class.find(:claude)).to be_a(AiCli::Provider::Claude)
    expect(described_class.find("gemini")).to be_nil
    expect(described_class.find(nil)).to be_nil
  end

  it "raises CommandError listing the choices for an unknown provider" do
    expect { described_class.fetch("gemini") }
      .to raise_error(AiCli::CommandError, 'unknown AGENT "gemini" (expected one of claude, cursor, codex)')
  end

  it "declares what each provider supports" do
    expect(described_class.fetch("claude").capabilities).to eq(AiCli::Provider::Capabilities.new(tool_lists: true, model: true, effort: true, mcp: :flag))
    expect(described_class.fetch("codex").capabilities).to eq(AiCli::Provider::Capabilities.new(tool_lists: false, model: true, effort: true, mcp: :overrides))
    expect(described_class.fetch("cursor").capabilities).to eq(AiCli::Provider::Capabilities.new(tool_lists: false, model: false, effort: false, mcp: :file))
  end
end
