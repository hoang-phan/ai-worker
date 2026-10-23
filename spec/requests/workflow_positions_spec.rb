require "rails_helper"

RSpec.describe "WorkflowPositions", type: :request, active_job_test_adapter: true do
  include ActiveJob::TestHelper

  let_tmpdir(:local_directory, "workflow-positions-request-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "SPEC-1", status: :errored, github_pr_url: "https://github.com/org/repo/pull/7")
  end

  describe "POST move" do
    let!(:first) { build_jira_workflow(project, jira_ticket: "A-1", github_reviewer: "x", position: 1) }
    let!(:second) { build_jira_workflow(project, jira_ticket: "A-2", github_reviewer: "x", position: 1) }
    let!(:third) { build_jira_workflow(project, jira_ticket: "A-3", github_reviewer: "x", position: 3) }

    it "moves a workflow up, even when positions were duplicated" do
      post move_project_workflow_path(project, third, direction: "up")

      expect(response).to redirect_to(project_path(project))
      expect(project.workflows.order(:position).pluck(:id)).to eq([ first.id, third.id, second.id ])
    end

    it "moves a workflow down" do
      post move_project_workflow_path(project, first, direction: "down")

      expect(project.workflows.order(:position).pluck(:id)).to eq([ second.id, first.id, third.id ])
    end

    it "leaves the order alone at the ends" do
      post move_project_workflow_path(project, first, direction: "up")

      expect(project.workflows.order(:position).pluck(:id)).to eq([ first.id, second.id, third.id ])
    end

    it "rejects an unknown direction" do
      post move_project_workflow_path(project, first, direction: "sideways")

      expect(flash[:alert]).to eq("Unknown direction.")
    end
  end
end
