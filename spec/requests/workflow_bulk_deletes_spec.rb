require "rails_helper"

RSpec.describe "WorkflowBulkDeletes", type: :request do
  let_jira_project("workflow-bulk-deletes-spec")
  let!(:a) { build_jira_workflow(project, jira_ticket: "BD-1", github_reviewer: "x") }
  let!(:b) { build_jira_workflow(project, jira_ticket: "BD-2", github_reviewer: "x") }
  let!(:c) { build_jira_workflow(project, jira_ticket: "BD-3", github_reviewer: "x") }

  it "deletes only the selected workflows and keeps the status filter" do
    delete bulk_destroy_project_workflows_path(project, status: "pending"), params: { workflow_ids: [ a.id, b.id ] }

    expect(response).to redirect_to(project_path(project, status: "pending"))
    expect(project.workflows.pluck(:id)).to eq([ c.id ])
  end

  it "alerts when nothing is selected" do
    delete bulk_destroy_project_workflows_path(project)

    expect(flash[:alert]).to eq("Select at least one workflow.")
    expect(project.workflows.count).to eq(3)
  end

  it "ignores workflows from other projects" do
    other_project = build_jira_project(local_directory: Dir.mktmpdir("bulk-delete-other"), name: "other-bulk-delete")
    other = build_jira_workflow(other_project, jira_ticket: "OT-1", github_reviewer: "x")

    delete bulk_destroy_project_workflows_path(project), params: { workflow_ids: [ a.id, other.id ] }

    expect(Workflow.exists?(other.id)).to be(true)
    expect(project.workflows.count).to eq(2)
  end
end
