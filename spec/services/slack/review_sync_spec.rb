require "rails_helper"

RSpec.describe Slack::ReviewSync do
  let(:dir) { Dir.mktmpdir("review-sync-spec") }
  let(:project) do
    Project.create!(name: "ReviewSync spec #{SecureRandom.hex(4)}", kind: :jira, local_directory: dir, repo_full_name: "acme/widgets",
                    slack_mention: "@reviewer")
  end
  let(:github) { instance_double(Github::Client, current_login: "me", pr_info: nil) }
  let(:sync) { described_class.new(project) }
  let(:pr_url) { "https://github.com/acme/widgets/pull/12" }
  let(:slack_url) { "https://acme.slack.com/archives/C0123456789/p1760000000123456" }
  let(:mention) { { "slack_url" => slack_url, "pr_urls" => [ pr_url ] } }

  before { allow(Github::Client).to receive(:new).and_return(github) }

  after do
    project.destroy
    FileUtils.remove_entry(dir) if dir.start_with?(Dir.tmpdir) && File.exist?(dir)
  end

  def stub_pr(url, state: "OPEN", author: "someone")
    allow(github).to receive(:pr_info).with(url).and_return("state" => state, "author" => author)
  end

  describe "#blockers" do
    it "is empty for a configured project" do
      expect(sync.blockers).to be_empty
    end

    it "lists every missing prerequisite" do
      project.update_columns(kind: Project.kinds[:personal], repo_full_name: nil, slack_mention: nil)

      expect(sync.blockers).to contain_exactly("project kind is not jira", "GitHub repo is not set", "Slack mention is not set")
    end
  end

  describe "#import" do
    it "returns blockers without touching GitHub when blocked" do
      project.update_columns(slack_mention: nil)

      result = sync.import([ mention ])

      expect(result.blockers).to eq([ "Slack mention is not set" ])
      expect(Github::Client).not_to have_received(:new)
    end

    it "creates a pr_review workflow for an open PR by someone else" do
      stub_pr(pr_url)

      result = sync.import([ mention ])

      expect(result.created).to eq([ pr_url ])
      workflow = project.workflows.pr_review.last
      expect([ workflow.slack_url, workflow.github_pr_url, workflow.status, workflow.position ]).to eq([ slack_url, pr_url, "implementing", 1 ])
    end

    it "ignores PRs from other repos" do
      other = "https://github.com/other/repo/pull/3"

      result = sync.import([ { "slack_url" => slack_url, "pr_urls" => [ other ] } ])

      expect(result.created).to be_empty
      expect(result.skipped).to be_empty
      expect(github).not_to have_received(:pr_info)
    end

    it "skips already-imported (slack_url, pr_url) pairs but imports the same PR from another message" do
      project.workflows.create!(kind: :pr_review, slack_url: slack_url, github_pr_url: pr_url, position: 1)
      stub_pr(pr_url)

      same = sync.import([ mention ])
      other = sync.import([ { "slack_url" => "#{slack_url}9", "pr_urls" => [ pr_url ] } ])

      expect(same.skipped).to eq([ pr_url ])
      expect(same.skipped_reasons).to eq("already imported" => 1)
      expect(other.created).to eq([ pr_url ])
    end

    it "skips non-OPEN PRs with the state as the reason" do
      stub_pr(pr_url, state: "MERGED")

      result = sync.import([ mention ])

      expect(result.skipped).to eq([ pr_url ])
      expect(result.skipped_reasons).to eq("merged" => 1)
      expect(project.workflows.count).to eq(0)
    end

    it "skips the user's own PRs case-insensitively" do
      stub_pr(pr_url, author: "ME")

      result = sync.import([ mention ])

      expect(result.skipped).to eq([ pr_url ])
      expect(result.skipped_reasons).to eq("own PR" => 1)
    end

    it "records Github::CommandError in failed and carries on" do
      second = "https://github.com/acme/widgets/pull/13"
      allow(github).to receive(:pr_info).with(pr_url).and_raise(Github::CommandError, "gh exploded")
      stub_pr(second)

      result = sync.import([ { "slack_url" => slack_url, "pr_urls" => [ pr_url, second ] } ])

      expect(result.failed).to eq([ "#{pr_url}: gh exploded" ])
      expect(result.created).to eq([ second ])
    end
  end

  describe "Result#summary" do
    def result(skipped:, reasons:)
      described_class::Result.new(blockers: [], created: [ 1 ], skipped: skipped, failed: [ "x" ], skipped_reasons: reasons)
    end

    it "omits the breakdown when nothing was skipped for a reason" do
      expect(result(skipped: [], reasons: Hash.new(0)).summary).to eq("created 1, skipped 0, failed 1")
    end

    it "appends the skipped reasons breakdown" do
      expect(result(skipped: %w[a b c], reasons: { "merged" => 2, "duplicate" => 1 }).summary)
        .to eq("created 1, skipped 3 (2 merged, 1 duplicate), failed 1")
    end
  end
end
