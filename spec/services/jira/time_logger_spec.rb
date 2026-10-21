require "rails_helper"

RSpec.describe Jira::TimeLogger do
  let(:kind) { :jira }
  let(:base_url) { "https://example.atlassian.net" }
  let(:project) { Project.create!(name: "Logger spec", kind: kind, repo_full_name: "org/repo", local_directory: "/tmp", jira_base_url: base_url) }
  let(:ticket) { "LOG-1" }
  let(:workflow) { project.workflows.create!(jira_ticket: ticket, branch_name: "log-1", github_reviewer: "x", task_description: "Spec task") }
  let(:client) { instance_double(Jira::WorklogClient, add_worklog: "10001") }
  let(:factory) { ->(_base_url) { client } }
  let(:started_at) { Time.zone.local(2026, 10, 20, 9) }
  let(:planner) { instance_double(Jira::TimeSlotPlanner, next_start: started_at) }

  subject(:logger) { described_class.new(client_factory: factory, planner: planner) }

  it "creates a TimeLog after the Jira worklog" do
    log = logger.log(workflow, 1.5)

    expect(client).to have_received(:add_worklog).with("LOG-1", started_at: started_at, seconds: 5400)
    expect(log).to be_persisted
    expect(log).to have_attributes(workflow: workflow, ticket_key: "LOG-1", seconds: 5400, started_at: started_at, jira_worklog_id: "10001")
  end

  context "when the project is not a Jira project" do
    let(:kind) { :personal }

    it "raises and logs nothing" do
      expect { logger.log(workflow, 1) }.to raise_error(Jira::WorklogError, /only Jira development workflows/)
      expect(TimeLog.where(workflow: workflow)).to be_empty
    end
  end

  context "when the Jira site URL is missing" do
    let(:base_url) { nil }

    it "raises" do
      expect { logger.log(workflow, 1) }.to raise_error(Jira::WorklogError, /Jira site URL is not set/)
      expect(client).not_to have_received(:add_worklog)
    end
  end

  context "when no ticket key can be found" do
    let(:ticket) { "no key here" }

    it "raises" do
      expect { logger.log(workflow, 1) }.to raise_error(Jira::WorklogError, /no Jira ticket key found/)
      expect(client).not_to have_received(:add_worklog)
    end
  end
end
