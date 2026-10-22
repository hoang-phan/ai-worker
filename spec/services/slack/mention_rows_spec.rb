require "rails_helper"

RSpec.describe Slack::MentionRows do
  let(:pr) { "https://github.com/acme/app/pull/1" }
  let(:slack) { "https://acme.slack.com/archives/C1/p1" }

  it "keeps valid rows" do
    rows = [ { "slack_url" => slack, "pr_urls" => [ pr ] } ]

    expect(described_class.call(rows)).to eq(rows)
  end

  it "drops non-hash rows" do
    expect(described_class.call([ nil, "x", 1, [ pr ] ])).to eq([])
  end

  it "drops rows with a blank slack_url" do
    rows = [ { "slack_url" => "  ", "pr_urls" => [ pr ] }, { "pr_urls" => [ pr ] } ]

    expect(described_class.call(rows)).to eq([])
  end

  it "drops rows without any valid PR url" do
    rows = [
      { "slack_url" => slack, "pr_urls" => [] },
      { "slack_url" => slack },
      { "slack_url" => slack, "pr_urls" => [ "https://github.com/acme/app/issues/1", "nope", nil ] }
    ]

    expect(described_class.call(rows)).to eq([])
  end

  it "keeps only valid PR urls, stripped and de-duplicated" do
    other = "https://github.com/acme/app/pull/2"
    rows = [ { "slack_url" => " #{slack} ", "pr_urls" => [ " #{pr} ", pr, "junk", other ] } ]

    expect(described_class.call(rows)).to eq([ { "slack_url" => slack, "pr_urls" => [ pr, other ] } ])
  end

  it "accepts a single string as pr_urls" do
    expect(described_class.call([ { "slack_url" => slack, "pr_urls" => pr } ])).to eq([ { "slack_url" => slack, "pr_urls" => [ pr ] } ])
  end
end
