require "rails_helper"

RSpec.describe Jira::TicketImporter do
  let(:dir) { Dir.mktmpdir("ticket-importer-spec") }
  let(:project) do
    build_jira_project(local_directory: dir, jira_base_url: "https://acme.atlassian.net", jira_assignee: "me@example.com",
                    default_reviewers: "alice,bob", default_skills: "rails,testing")
  end
  let(:result) { Jira::TicketSync::Result.new(blockers: [], created: [], skipped: [], failed: []) }

  after do
    project.destroy
    FileUtils.remove_entry(dir) if dir.start_with?(Dir.tmpdir) && File.exist?(dir)
  end

  def import(issues)
    described_class.new(project).import(issues, result)
  end

  describe "#import" do
    it "creates workflows with ticket URL, branch, default reviewers/skills and increasing positions" do
      result = import([ { "key" => "UNS-1" }, { "key" => "UNS-2" } ])

      expect(result.created).to eq(%w[UNS-1 UNS-2])
      workflows = project.workflows.order(:position)
      expect(workflows.map(&:jira_ticket)).to eq(%w[https://acme.atlassian.net/browse/UNS-1 https://acme.atlassian.net/browse/UNS-2])
      expect(workflows.map(&:branch_name)).to eq(%w[UNS-1 UNS-2])
      expect(workflows.map(&:github_reviewer).uniq).to eq([ "alice,bob" ])
      expect(workflows.map(&:skills).uniq).to eq([ "rails,testing" ])
      expect(workflows.map(&:position)).to eq([ 1, 2 ])
    end

    it "skips keys that already have a workflow, including ones stored as full browse URLs" do
      build_jira_workflow(project, jira_ticket: "https://acme.atlassian.net/browse/UNS-1", branch_name: "UNS-1", github_reviewer: "alice", position: 1)
      build_jira_workflow(project, jira_ticket: "UNS-2", branch_name: "UNS-2", github_reviewer: "alice", position: 2)

      result = import([ { "key" => "UNS-1" }, { "key" => "UNS-2" }, { "key" => "UNS-3" } ])

      expect(result.skipped).to eq(%w[UNS-1 UNS-2])
      expect(result.created).to eq([ "UNS-3" ])
      expect(project.workflows.count).to eq(3)
    end

    it "skips a key repeated within the same batch" do
      result = import([ { "key" => "UNS-1" }, { "key" => "UNS-1" } ])

      expect(result.created).to eq([ "UNS-1" ])
      expect(result.skipped).to eq([ "UNS-1" ])
    end

    it "ignores blank keys" do
      result = import([ { "key" => "" }, { "key" => nil }, {} ])

      expect(result.created).to be_empty
      expect(result.skipped).to be_empty
      expect(result.failed).to be_empty
    end

    it "reports validation failures in failed" do
      allow_any_instance_of(Workflow).to receive(:save).and_wrap_original do |m|
        m.receiver.errors.add(:base, "boom")
        false
      end

      result = import([ { "key" => "UNS-9" } ])

      expect(result.failed).to eq([ "UNS-9: boom" ])
      expect(result.created).to be_empty
    end
  end
end
