require "rails_helper"

RSpec.describe Github::ReviewDecision do
  def review(login, state)
    { "author" => { "login" => login }, "state" => state }
  end

  it "filters reviewers case-insensitively" do
    reviews = [ review("Mallory", "APPROVED"), review("Alice", "CHANGES_REQUESTED") ]

    expect(described_class.call(reviews, [ "ALICE" ])).to eq("CHANGES_REQUESTED")
  end

  it "considers every review when no reviewers are specified" do
    expect(described_class.call([ review("anyone", "APPROVED") ], [])).to eq("APPROVED")
  end

  it "prefers an approval over a change request" do
    reviews = [ review("alice", "CHANGES_REQUESTED"), review("bob", "APPROVED") ]

    expect(described_class.call(reviews, %w[alice bob])).to eq("APPROVED")
  end

  it "treats a comment-only review like a change request" do
    expect(described_class.call([ review("alice", "COMMENTED") ], [ "alice" ])).to eq("CHANGES_REQUESTED")
  end

  it "still prefers an approval over a comment" do
    reviews = [ review("alice", "COMMENTED"), review("bob", "APPROVED") ]

    expect(described_class.call(reviews, %w[alice bob])).to eq("APPROVED")
  end

  it "ignores comments from users who are not assigned reviewers" do
    expect(described_class.call([ review("mallory", "COMMENTED") ], [ "alice" ])).to be_nil
  end

  it "returns nil when there are no reviews" do
    expect(described_class.call([], [ "alice" ])).to be_nil
  end
end
