require "rails_helper"

RSpec.describe Slack::MentionFetcher do
  it "needs slack_url and at least one matching PR URL" do
    Dir.mktmpdir do |tmp|
      stub_const("Slack::MentionFetcher::ROOT", Pathname(tmp))
      fetcher = described_class.new(double(id: 1))
      FileUtils.mkdir_p(Pathname(tmp).join("1"))
      Pathname(tmp).join("1", "pid").write("1")
      pr = "https://github.com/acme/app/pull/7"
      Pathname(tmp).join("1", "mentions.json").write([
        { slack_url: "https://x.slack.com/archives/C1/p1", pr_urls: [ pr, pr, "https://example.com/nope" ] },
        { slack_url: "", pr_urls: [ pr ] },
        { slack_url: "https://x.slack.com/archives/C1/p2", pr_urls: [ "https://example.com/nope" ] },
        "junk"
      ].to_json)
      allow(AiCli::Runner).to receive(:poll).and_return([ :completed, nil ])

      expect(fetcher.poll).to eq([ { "slack_url" => "https://x.slack.com/archives/C1/p1", "pr_urls" => [ pr ] } ])
    end
  end
end
