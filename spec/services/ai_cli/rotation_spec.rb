require "rails_helper"

RSpec.describe AiCli::Rotation do
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(store) }

  it "is off by default" do
    expect(described_class).not_to be_enabled
    expect(described_class.next_provider).to be_nil
  end

  it "cycles by weight, then repeats" do
    described_class.weights = { "claude" => 2, "codex" => 1 }

    picks = Array.new(6) { described_class.next_provider }

    expect(picks).to eq(%w[claude claude codex claude claude codex])
  end

  it "rejects unknown agents and negative weights" do
    expect { described_class.weights = { "nope" => 1 } }.to raise_error(ArgumentError, /unknown agent/)
    expect { described_class.weights = { "claude" => -1 } }.to raise_error(ArgumentError, /negative/)
  end
end
