require "rails_helper"

RSpec.describe Bugsnag::TriageSync do
  let_tmpdir(:dir, "triage-sync-spec")
  let(:project) do
    build_jira_project(local_directory: dir, jira_base_url: "https://acme.atlassian.net")
  end
  let(:bugsnag_sync) { project.bugsnag_syncs.create!(bugsnag_project: "web", jira_project: "WEB") }
  let(:triager) { instance_double(Bugsnag::Triager) }
  let(:sync) { described_class.new(bugsnag_sync, triager: triager) }

  describe "#triager" do
    it "returns the injected triager" do
      expect(sync.triager).to be(triager)
    end

    it "builds and memoizes a Triager for the sync by default" do
      default = described_class.new(bugsnag_sync)

      expect(default.triager).to be_a(Bugsnag::Triager)
      expect(default.triager).to be(default.triager)
    end
  end

  describe "#blockers" do
    it "is empty for a ready project" do
      expect(sync.blockers).to eq([])
    end

    it "lists the missing preconditions" do
      missing_directory = File.join(Dir.tmpdir, "missing-triage-sync-#{SecureRandom.uuid}")
      project.update_columns(kind: Project.kinds[:personal], jira_base_url: nil, local_directory: missing_directory)

      expect(sync.blockers).to eq([
        "project kind is not jira",
        "Jira site URL is not set",
        "local directory does not exist"
      ])
    end
  end

  describe "#import" do
    it "merges rows into the ledger and reports the added keys" do
      result = sync.import([ { "bugsnag_id" => "abc123def456", "jira_key" => "WEB-1" } ])

      expect(result.added).to eq(%w[WEB-1])
      expect(bugsnag_sync.reload.ledger).to include("abc123def456")
    end

    it "adds nothing when re-importing known rows" do
      rows = [ { "bugsnag_id" => "abc123def456", "jira_key" => "WEB-1" } ]
      sync.import(rows)

      expect(sync.import(rows).added).to eq([])
    end
  end

  describe "Result#summary" do
    it "lists the newly added keys" do
      expect(described_class::Result.new(added: %w[UNS-1 UNS-2]).summary).to eq("2 new ticket(s): UNS-1, UNS-2")
    end

    it "says nothing new when no keys were added" do
      expect(described_class::Result.new(added: []).summary).to eq("nothing new")
    end
  end
end
