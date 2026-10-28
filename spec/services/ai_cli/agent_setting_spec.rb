require "rails_helper"

RSpec.describe AiCli::AgentSetting do
  describe ".current" do
    it "returns a valid cached value" do
      described_class.current = "codex"

      expect(described_class.current(env: { "AGENT" => "cursor" })).to eq("codex")
    end

    it "falls back to ENV[AGENT] when the cached value is unknown" do
      Rails.cache.write(described_class::CACHE_KEY, "bogus")

      expect(described_class.current(env: { "AGENT" => "cursor" })).to eq("cursor")
    end

    it "falls back to claude without a cached value or ENV[AGENT]" do
      expect(described_class.current(env: {})).to eq("claude")
    end
  end

  describe ".current=" do
    it "rejects unknown names without writing" do
      expect { described_class.current = "bogus" }.to raise_error(ArgumentError, /unknown agent "bogus"/)
      expect(Rails.cache.read(described_class::CACHE_KEY)).to be_nil
    end

    it "writes valid names" do
      described_class.current = "codex"

      expect(Rails.cache.read(described_class::CACHE_KEY)).to eq("codex")
    end
  end

  describe ".available" do
    it "lists the known agents" do
      expect(described_class.available).to eq(AiCli::Providers.names)
    end
  end
end
