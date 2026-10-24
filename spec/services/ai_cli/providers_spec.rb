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
end
