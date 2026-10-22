require "rails_helper"

RSpec.describe AiCli::AgentSetting do
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(store) }

  describe ".current" do
    it "returns a valid cached value" do
      store.write("ai_cli/agent", "codex")
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("AGENT").and_return("cursor")

      expect(described_class.current).to eq("codex")
    end

    it "falls back to ENV[AGENT] when the cached value is unknown" do
      store.write("ai_cli/agent", "bogus")
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("AGENT").and_return("cursor")

      expect(described_class.current).to eq("cursor")
    end

    it "falls back to claude without a cached value or ENV[AGENT]" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("AGENT").and_return(nil)

      expect(described_class.current).to eq("claude")
    end
  end

  describe ".current=" do
    it "rejects unknown names without writing" do
      expect { described_class.current = "bogus" }.to raise_error(ArgumentError, /unknown agent "bogus"/)
      expect(store.read("ai_cli/agent")).to be_nil
    end

    it "writes valid names" do
      described_class.current = "codex"

      expect(store.read("ai_cli/agent")).to eq("codex")
    end
  end

  describe ".available" do
    it "lists the known agents" do
      expect(described_class.available).to eq(AiCli::Providers.names)
    end
  end
end
