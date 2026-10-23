require "rails_helper"

RSpec.describe Projects::WorkflowList do
  let(:project) { build_jira_project }
  let!(:first) { build_jira_workflow(project, jira_ticket: "TEST-101", status: :pending) }
  let!(:middle) { build_jira_workflow(project, jira_ticket: "TEST-102", status: :reviewing) }
  let!(:last) { build_jira_workflow(project, jira_ticket: "TEST-103", status: :pending) }

  it "ignores an invalid status" do
    list = described_class.new(project, status: "bogus")

    expect(list.status_filter).to be_nil
    expect(list.workflows.map(&:id)).to eq([ first.id, middle.id, last.id ])
  end

  it "ignores a blank status" do
    expect(described_class.new(project, status: "").status_filter).to be_nil
  end

  it "filters by a valid status" do
    list = described_class.new(project, status: "reviewing")

    expect(list.status_filter).to eq("reviewing")
    expect(list.workflows.map(&:id)).to eq([ middle.id ])
  end

  it "computes first and last ids over the unfiltered list" do
    list = described_class.new(project, status: "reviewing")

    expect(list.first_id).to eq(first.id)
    expect(list.last_id).to eq(last.id)
  end

  it "has nil ends for an empty project" do
    list = described_class.new(build_jira_project)

    expect(list.first_id).to be_nil
    expect(list.last_id).to be_nil
  end

  it "keys logged seconds by jira_key" do
    TimeLog.create!(ticket_key: first.jira_key, started_at: Time.current, seconds: 3600)
    TimeLog.create!(ticket_key: first.jira_key, started_at: Time.current, seconds: 1800)
    list = described_class.new(project)

    expect(list.logged_seconds_for(first)).to eq(5400)
    expect(list.logged_seconds_for(middle)).to be_nil
  end
end
