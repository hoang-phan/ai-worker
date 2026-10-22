require "rails_helper"

RSpec.describe Jira::LoggedTime do
  let(:kind) { :jira }
  let(:ticket) { "LT-1" }
  let(:project) { Project.create!(name: "Logged time spec", kind: kind, repo_full_name: "org/repo", local_directory: "/tmp", jira_base_url: "https://example.atlassian.net") }
  let(:workflow) { project.workflows.create!(jira_ticket: ticket, branch_name: "lt-1", github_reviewer: "x", task_description: "Spec task") }
  let(:client) { instance_double(Jira::WorklogClient, logged_seconds: 5400) }
  let(:factory) { instance_double(Proc, call: client) }

  subject(:logged_time) { described_class.new(client_factory: factory) }

  it "returns the client's logged seconds for the ticket key" do
    expect(logged_time.seconds_for(workflow)).to eq(5400)
    expect(factory).to have_received(:call).with("https://example.atlassian.net")
    expect(client).to have_received(:logged_seconds).with("LT-1")
  end

  context "when the workflow is ineligible" do
    let(:kind) { :personal }

    it "returns nil without building a client" do
      expect(logged_time.seconds_for(workflow)).to be_nil
      expect(factory).not_to have_received(:call)
    end
  end

  context "when no ticket key is found" do
    let(:ticket) { "nothing" }

    it "returns nil" do
      expect(logged_time.seconds_for(workflow)).to be_nil
      expect(factory).not_to have_received(:call)
    end
  end

  it "lets WorklogError propagate" do
    allow(client).to receive(:logged_seconds).and_raise(Jira::WorklogError, "Jira is down")

    expect { logged_time.seconds_for(workflow) }.to raise_error(Jira::WorklogError, "Jira is down")
  end
end
