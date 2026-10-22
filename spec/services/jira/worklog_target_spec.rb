require "rails_helper"

RSpec.describe Jira::WorklogTarget do
  let(:kind) { :jira }
  let(:base_url) { "https://example.atlassian.net" }
  let(:ticket) { "TGT-1" }
  let(:workflow_kind) { :development }
  let(:project) { Project.create!(name: "Target spec", kind: kind, repo_full_name: "org/repo", local_directory: "/tmp", jira_base_url: base_url) }
  let(:workflow) do
    project.workflows.create!(jira_ticket: ticket, branch_name: "tgt-1", github_reviewer: "x", task_description: "Spec task", kind: workflow_kind)
  end

  subject(:target) { described_class.new(workflow) }

  it "has no problem and exposes the site URL and key" do
    expect(target.problem).to be_nil
    expect(target.base_url).to eq(base_url)
    expect(target.key).to eq("TGT-1")
  end

  context "when the ticket is a URL" do
    let(:ticket) { "https://example.atlassian.net/browse/TGT-42?focusedId=1" }

    it "extracts the key" do
      expect(target.key).to eq("TGT-42")
      expect(target.problem).to be_nil
    end
  end

  context "when the project is not a Jira project" do
    let(:kind) { :personal }

    it { expect(target.problem).to eq("only Jira development workflows can log time") }
  end

  context "when the workflow is a runbook" do
    let(:workflow_kind) { :runbook }

    it { expect(target.problem).to eq("only Jira development workflows can log time") }
  end

  context "when the Jira site URL is missing" do
    let(:base_url) { nil }

    it { expect(target.problem).to eq("Jira site URL is not set on the project") }
  end

  context "when no ticket key can be found" do
    let(:ticket) { "no key here" }

    it "reports the problem and has no key" do
      expect(target.key).to be_nil
      expect(target.problem).to eq("no Jira ticket key found")
    end
  end
end
