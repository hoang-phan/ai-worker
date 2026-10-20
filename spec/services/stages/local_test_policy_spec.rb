require "rails_helper"

RSpec.describe Stages::LocalTestPolicy do
  describe ".outcome" do
    # result, completed rounds, failed, retest, rounds exhausted, auto-merge
    [
      ["PASSED", 0, false, false, false, true],
      ["PASSED", 1, false, false, false, true],
      ["PASSED", 2, false, false, false, true],
      ["PASSED", 3, false, false, false, true],
      ["FAILED", 0, true, true, false, false],
      ["FAILED", 1, true, true, false, false],
      ["FAILED", 2, true, false, true, false],
      ["FAILED", 3, true, false, true, false],
      ["BLOCKED", 0, false, false, false, false],
      ["BLOCKED", 1, false, false, false, false],
      ["BLOCKED", 2, false, false, false, false],
      ["BLOCKED", 3, false, false, false, false]
    ].each do |result, rounds, failed, retest, exhausted, auto_merge|
      it "#{result} after #{rounds} completed rounds" do
        outcome = described_class.outcome(result: result, completed_rounds: rounds)

        expect(outcome.failed?).to eq(failed)
        expect(outcome.retest?).to eq(retest)
        expect(outcome.rounds_exhausted?).to eq(exhausted)
        expect(outcome.auto_merge?).to eq(auto_merge)
      end
    end

    it "matches result names case-insensitively" do
      expect(described_class.outcome(result: "passed", completed_rounds: 0).auto_merge?).to be(true)
      expect(described_class.outcome(result: "failed", completed_rounds: 0).failed?).to be(true)
    end
  end

  describe ".retest_after_fix?" do
    # ready, completed rounds, feedback pending, agent requested, retest
    [
      [false, 0, true, true, false],
      [true, 3, true, true, false],
      [true, 0, false, false, false],
      [true, 0, true, false, true],
      [true, 0, false, true, true]
    ].each do |ready, rounds, feedback, requested, retest|
      it "ready=#{ready}, rounds=#{rounds}, feedback=#{feedback}, requested=#{requested}" do
        expect(described_class.retest_after_fix?(
          local_test_ready: ready,
          completed_rounds: rounds,
          feedback_pending: feedback,
          retest_requested: requested
        )).to eq(retest)
      end
    end
  end

  describe ".feedback" do
    it "returns the agent's feedback block" do
      expect(described_class.feedback(output_block: "Login button is broken", pr_url: "https://example.test/pr/1"))
        .to eq("Login button is broken")
    end

    it "falls back to the PR comment URL" do
      pr_url = "https://github.com/org/repo/pull/1"

      expect(described_class.feedback(output_block: nil, pr_url: pr_url)).to include(pr_url)
    end
  end
end
