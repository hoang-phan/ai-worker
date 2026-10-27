require "rails_helper"

RSpec.describe Slack::MentionFetcher do
  let(:run) { FakeDetachedRun.new }
  let(:project) { double(id: 1, slack_mention: "@me", repo_full_name: "acme/app") }
  let(:root) { Pathname("/tmp/slack-root") }
  let(:fetcher) { described_class.new(project, root: root, run: run) }

  it "needs slack_url and at least one matching PR URL" do
    tmp = make_tmpdir("slack-fetcher-spec")
    runner = double("AiCli::Runner", poll: [ :completed, nil ])
    run = AiCli::DetachedRun.new(dir: Pathname(tmp).join("1"), result_name: "mentions.json", stale_after: described_class::STALE_AFTER,
                                 error_class: Slack::FetchError, runner: runner)
    fetcher = described_class.new(project, root: Pathname(tmp), run: run)
    FileUtils.mkdir_p(Pathname(tmp).join("1"))
    Pathname(tmp).join("1", "pid").write("1")
    pr = "https://github.com/acme/app/pull/7"
    Pathname(tmp).join("1", "mentions.json").write([
      { slack_url: "https://x.slack.com/archives/C1/p1", pr_urls: [ pr, pr, "https://example.com/nope" ] },
      { slack_url: "", pr_urls: [ pr ] },
      { slack_url: "https://x.slack.com/archives/C1/p2", pr_urls: [ "https://example.com/nope" ] },
      "junk"
    ].to_json)

    expect(fetcher.poll).to eq([ { "slack_url" => "https://x.slack.com/archives/C1/p1", "pr_urls" => [ pr ] } ])
  end

  describe "#start" do
    it "runs in the project dir with ALLOWED_TOOLS and a prompt naming mentions.json" do
      run.result_path = root.join("1", "mentions.json")
      fetcher.start

      expect(run.started[:cwd]).to eq(root.join("1"))
      expect(run.started[:allowed_tools]).to eq(described_class::ALLOWED_TOOLS)
      expect(run.started[:prompt]).to include(root.join("1", "mentions.json").to_s)
    end

    it "looks back FIRST_LOOKBACK when it never ran" do
      now = Time.utc(2026, 5, 1, 12)
      expected = now - described_class::FIRST_LOOKBACK
      fetcher = described_class.new(project, root: root, run: run, clock: -> { now })

      fetcher.start

      expect(run.started[:prompt]).to include("Only consider messages posted after #{expected.utc.iso8601}")
    end

    it "starts OVERLAP before the last start otherwise" do
      last = Time.utc(2026, 5, 1, 8)
      run.last_started_at = last
      expected = last - described_class::OVERLAP

      fetcher.start

      expect(run.started[:prompt]).to include("Only consider messages posted after #{expected.utc.iso8601}")
    end
  end

  describe "#poll" do
    it "passes rows through MentionRows" do
      pr = "https://github.com/acme/app/pull/7"
      run.rows = [ { "slack_url" => "https://x.slack.com/archives/C1/p1", "pr_urls" => [ pr ] }, { "slack_url" => "" }, "junk" ]

      expect(fetcher.poll).to eq([ { "slack_url" => "https://x.slack.com/archives/C1/p1", "pr_urls" => [ pr ] } ])
    end
  end

  it_behaves_like "a detached-run fetcher"
end
