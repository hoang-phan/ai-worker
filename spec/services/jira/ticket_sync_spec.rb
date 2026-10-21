require "rails_helper"

RSpec.describe Jira::TicketSync do
  let(:dir) { Dir.mktmpdir("ticket-sync-spec") }
  let(:project) do
    Project.create!(name: "TicketSync spec #{SecureRandom.hex(4)}", kind: :jira, local_directory: dir, repo_full_name: "acme/widgets",
                    jira_base_url: "https://acme.atlassian.net", jira_assignee: "me@example.com",
                    default_reviewers: "alice,bob", default_skills: "rails,testing")
  end
  let(:jira_sync) { project.jira_syncs.create! }
  let(:sync) { described_class.new(jira_sync) }

  after do
    project.destroy
    FileUtils.remove_entry(dir) if dir.start_with?(Dir.tmpdir) && File.exist?(dir)
  end

  describe "#blockers" do
    it "is empty for a fully configured project" do
      expect(sync.blockers).to be_empty
    end

    it "lists every missing prerequisite" do
      project.update_columns(kind: Project.kinds[:personal], jira_base_url: nil, jira_assignee: nil, default_reviewers: nil)

      expect(sync.blockers).to contain_exactly(
        "project kind is not jira",
        "Jira site URL is not set",
        "assignee is not set",
        "default GitHub reviewers are not set (workflows require a reviewer)"
      )
    end
  end

  describe "#import" do
    it "creates nothing and reports blockers when blocked" do
      project.update_columns(jira_assignee: nil)

      result = sync.import([ { "key" => "UNS-1" } ])

      expect(result.blockers).to eq([ "assignee is not set" ])
      expect(result.created).to be_empty
      expect(project.workflows.count).to eq(0)
    end

    it "creates workflows with ticket URL, branch, default reviewers/skills and increasing positions" do
      result = sync.import([ { "key" => "UNS-1" }, { "key" => "UNS-2" } ])

      expect(result.created).to eq(%w[UNS-1 UNS-2])
      workflows = project.workflows.order(:position)
      expect(workflows.map(&:jira_ticket)).to eq(%w[https://acme.atlassian.net/browse/UNS-1 https://acme.atlassian.net/browse/UNS-2])
      expect(workflows.map(&:branch_name)).to eq(%w[UNS-1 UNS-2])
      expect(workflows.map(&:github_reviewer).uniq).to eq([ "alice,bob" ])
      expect(workflows.map(&:skills).uniq).to eq([ "rails,testing" ])
      expect(workflows.map(&:position)).to eq([ 1, 2 ])
    end

    it "skips keys that already have a workflow, including ones stored as full browse URLs" do
      project.workflows.create!(jira_ticket: "https://acme.atlassian.net/browse/UNS-1", branch_name: "UNS-1", github_reviewer: "alice", position: 1)
      project.workflows.create!(jira_ticket: "UNS-2", branch_name: "UNS-2", github_reviewer: "alice", position: 2)

      result = sync.import([ { "key" => "UNS-1" }, { "key" => "UNS-2" }, { "key" => "UNS-3" } ])

      expect(result.skipped).to eq(%w[UNS-1 UNS-2])
      expect(result.created).to eq([ "UNS-3" ])
      expect(project.workflows.count).to eq(3)
    end

    it "skips a key repeated within the same batch" do
      result = sync.import([ { "key" => "UNS-1" }, { "key" => "UNS-1" } ])

      expect(result.created).to eq([ "UNS-1" ])
      expect(result.skipped).to eq([ "UNS-1" ])
    end

    it "ignores blank keys" do
      result = sync.import([ { "key" => "" }, { "key" => nil }, {} ])

      expect(result.created).to be_empty
      expect(result.skipped).to be_empty
      expect(result.failed).to be_empty
    end

    it "reports validation failures in failed" do
      allow_any_instance_of(Workflow).to receive(:save).and_wrap_original do |m|
        m.receiver.errors.add(:base, "boom")
        false
      end

      result = sync.import([ { "key" => "UNS-9" } ])

      expect(result.failed).to eq([ "UNS-9: boom" ])
      expect(result.created).to be_empty
    end
  end

  describe "Result#summary" do
    it "counts created, skipped and failed" do
      result = described_class::Result.new(blockers: [], created: %w[A-1 A-2], skipped: %w[A-3], failed: [])

      expect(result.summary).to eq("created 2, skipped 1, failed 0")
    end
  end
end
