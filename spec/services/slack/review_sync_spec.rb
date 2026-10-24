require "rails_helper"

RSpec.describe Slack::ReviewSync do
  let_tmpdir(:dir, "review-sync-spec")
  let(:project) do
    build_jira_project(local_directory: dir, slack_mention: "@reviewer")
  end
  let(:github) { instance_double(Github::Client, current_login: "me", pr_info: nil) }
  let(:sync) { described_class.new(project, github: github) }
  let(:pr_url) { "https://github.com/acme/widgets/pull/12" }
  let(:slack_url) { "https://acme.slack.com/archives/C0123456789/p1760000000123456" }
  let(:mention) { { "slack_url" => slack_url, "pr_urls" => [ pr_url ] } }


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
      expect(github).not_to have_received(:current_login)
      expect(github).not_to have_received(:pr_info)
    end

    it "does not build a client when blocked" do
      project.update_columns(slack_mention: nil)
      allow(Github::Client).to receive(:new)

      described_class.new(project).import([ mention ])

      expect(Github::Client).not_to have_received(:new)
    end

    it "builds the client lazily when none is injected" do
      allow(Github::Client).to receive(:new).with(project).and_return(github)
      stub_pr(pr_url)

      result = described_class.new(project).import([ mention ])

      expect(result.created).to eq([ pr_url ])
      expect(Github::Client).to have_received(:new).once
    end

    it "delegates to ReviewImporter with a fresh result and the GitHub client" do
      importer = instance_double(Slack::ReviewImporter)
      allow(Slack::ReviewImporter).to receive(:new).with(project, github: github).and_return(importer)
      allow(importer).to receive(:import) { |_mentions, result| result }

      result = sync.import([ mention ])

      expect(importer).to have_received(:import).with([ mention ], result)
      expect(result).to have_attributes(blockers: [], created: [], skipped: [], failed: [], skipped_reasons: {})
    end

    it "imports end to end" do
      stub_pr(pr_url)

      result = sync.import([ mention ])

      expect(result.created).to eq([ pr_url ])
      expect(result.summary).to eq("created 1, skipped 0, failed 0")
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
