require "rails_helper"

RSpec.describe Stages::RunHistory do
  def history(*actions) = described_class.new(actions)

  describe "#last_action" do
    it "is the newest action" do
      expect(history("started", "completed").last_action).to eq("started")
    end

    it "is nil for an empty history" do
      expect(history.last_action).to be_nil
    end
  end

  describe "#consecutive_failures" do
    it "counts failed rows, ignoring interleaved started rows" do
      expect(history("started", "failed", "started", "failed", "failed").consecutive_failures).to eq(3)
    end

    it "stops at a success" do
      expect(history("failed", "failed", "completed", "failed").consecutive_failures).to eq(2)
    end

    it "stops at resumed" do
      expect(history("failed", "resumed", "failed", "failed").consecutive_failures).to eq(1)
    end

    it "is zero when the newest action is a success" do
      expect(history("completed", "failed").consecutive_failures).to eq(0)
    end

    it "is zero for an empty history" do
      expect(history.consecutive_failures).to eq(0)
    end
  end

  describe "#resolving_conflicts?" do
    it "is true when conflict_resolution_started is the newest action" do
      expect(history("conflict_resolution_started", "failed")).to be_resolving_conflicts
    end

    it "is false once something newer happened" do
      expect(history("failed", "conflict_resolution_started")).not_to be_resolving_conflicts
    end

    it "is false for an empty history" do
      expect(history).not_to be_resolving_conflicts
    end
  end

  describe "#completed_local_test_rounds" do
    it "counts every local_test_completed row" do
      expect(history("local_test_completed", "started", "local_test_completed", "failed").completed_local_test_rounds).to eq(2)
    end

    it "is zero for an empty history" do
      expect(history.completed_local_test_rounds).to eq(0)
    end
  end

  describe "#local_test_unfinished?" do
    it "is true when the newest run isn't a completion" do
      expect(history("started", "local_test_completed")).to be_local_test_unfinished
    end

    it "is false when the newest run is a completion" do
      expect(history("local_test_completed", "started")).not_to be_local_test_unfinished
    end

    it "is false for an empty history" do
      expect(history).not_to be_local_test_unfinished
    end
  end
end
