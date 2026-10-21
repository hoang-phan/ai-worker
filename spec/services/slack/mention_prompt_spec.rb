require "rails_helper"

RSpec.describe Slack::MentionPrompt do
  def build(**overrides)
    described_class.new(
      mention: "@reviewers", repo_full_name: "acme/app", since: Time.utc(2026, 1, 2, 3, 4, 5),
      mentions_file: "/tmp/slack/mentions.json", **overrides
    ).to_s
  end

  it "renders since as UTC ISO8601, even for a non-UTC time" do
    expect(build).to include("Only consider messages posted after 2026-01-02T03:04:05Z.")
    zoned = Time.new(2026, 1, 2, 13, 4, 5, "+10:00")
    expect(build(since: zoned)).to include("posted after 2026-01-02T03:04:05Z.")
  end

  it "interpolates the mention, repo and result file" do
    text = build
    expect(text).to include("find Slack messages that mention @reviewers,")
    expect(text).to include("repository acme/app (https://github.com/acme/app/pull/<number>)")
    expect(text).to include("\"pr_urls\":[\"https://github.com/acme/app/pull/42\"]")
    expect(text).to include("permalink of the message that mentions @reviewers.")
    expect(text).to include("Write the result to /tmp/slack/mentions.json as a JSON array")
  end
end
