require "rails_helper"

RSpec.describe Projects::RunBlockers do
  let(:project) { build_jira_project }
  let(:blockers) { described_class.new(project) }

  def self.check(name, message, failing:, passing:)
    describe "##{name}" do
      it "returns the message when blocked" do
        project.assign_attributes(failing)
        expect(blockers.public_send(name)).to eq(message)
      end

      it "returns nil when ready" do
        project.assign_attributes(passing)
        expect(blockers.public_send(name)).to be_nil
      end
    end
  end

  check :jira_kind, "project kind is not jira", failing: { kind: :personal }, passing: { kind: :jira }
  check :personal_kind, "project kind is not personal", failing: { kind: :jira }, passing: { kind: :personal }
  check :jira_site_url, "Jira site URL is not set", failing: { jira_base_url: "" }, passing: { jira_base_url: "https://x.atlassian.net" }
  check :assignee, "assignee is not set", failing: { jira_assignee: "" }, passing: { jira_assignee: "me" }
  check :default_reviewers, "default GitHub reviewers are not set (workflows require a reviewer)",
        failing: { default_reviewers: "" }, passing: { default_reviewers: "alice" }
  check :repo, "GitHub repo is not set", failing: { repo_full_name: "" }, passing: { repo_full_name: "acme/app" }
  check :slack_mention, "Slack mention is not set", failing: { slack_mention: "" }, passing: { slack_mention: "<@U1>" }
  check :brainstorm_goal, "no goal set", failing: { brainstorm_goal: "" }, passing: { brainstorm_goal: "ship it" }

  describe "#local_directory" do
    let(:dir) { Dir.mktmpdir("run-blockers-spec") }

    after { FileUtils.remove_entry(dir) if dir.start_with?(Dir.tmpdir) && File.exist?(dir) }

    it "returns the message when the directory is missing or blank" do
      project.local_directory = File.join(dir, "missing")
      expect(blockers.local_directory).to eq("local directory does not exist")
      project.local_directory = nil
      expect(blockers.local_directory).to eq("local directory does not exist")
    end

    it "returns nil when the directory exists" do
      project.local_directory = dir
      expect(blockers.local_directory).to be_nil
    end
  end

  describe "#messages" do
    it "returns only the failing checks, in the order asked" do
      project.assign_attributes(kind: :personal, jira_base_url: "", jira_assignee: "me")
      expect(blockers.messages(:jira_site_url, :assignee, :jira_kind))
        .to eq(["Jira site URL is not set", "project kind is not jira"])
    end

    it "returns an empty list when everything passes" do
      project.assign_attributes(jira_assignee: "me")
      expect(blockers.messages(:assignee)).to eq([])
    end
  end
end
