require "rails_helper"

RSpec.describe Stages::PrCheckDecision do
  def decide(review, local_test:, checks:)
    calls = []
    result = described_class.new(
      review_decision: review,
      local_test_failing: local_test,
      checks_failing: -> { calls << :checked; checks }
    ).call
    [ result, calls ]
  end

  # review, local test failing, checks failing, decision, actions, checks consulted
  [
    [ "APPROVED", false, false, :approved, [], true ],
    [ "APPROVED", false, true, :changes_requested, %w[checks_failing], true ],
    [ "APPROVED", true, false, :changes_requested, %w[local_test_failing], false ],
    [ "APPROVED", true, true, :changes_requested, %w[local_test_failing], false ],
    [ "CHANGES_REQUESTED", false, false, :changes_requested, [], false ],
    [ "CHANGES_REQUESTED", false, true, :changes_requested, [], false ],
    [ "CHANGES_REQUESTED", true, false, :changes_requested, %w[local_test_failing], false ],
    [ "CHANGES_REQUESTED", true, true, :changes_requested, %w[local_test_failing], false ],
    [ "REVIEW_REQUIRED", false, false, :pending, [], false ],
    [ "REVIEW_REQUIRED", false, true, :pending, [], false ],
    [ "REVIEW_REQUIRED", true, false, :pending, [], false ],
    [ "REVIEW_REQUIRED", true, true, :pending, [], false ],
    [ nil, false, false, :pending, [], false ],
    [ nil, false, true, :pending, [], false ],
    [ nil, true, false, :pending, [], false ],
    [ nil, true, true, :pending, [], false ]
  ].each do |review, local_test, checks, decision, actions, consulted|
    it "#{review.inspect}, local test #{local_test ? 'failing' : 'ok'}, checks #{checks ? 'failing' : 'ok'} => #{decision} #{actions}" do
      result, calls = decide(review, local_test: local_test, checks: checks)

      expect(result.decision).to eq(decision)
      expect(result.actions).to eq(actions)
      expect(calls.any?).to eq(consulted)
    end
  end
end
