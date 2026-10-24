require "rails_helper"

RSpec.describe "WorkflowTransitions", type: :request, active_job_test_adapter: true do
  include ActiveJob::TestHelper

  let_jira_project("workflow-transitions-request-spec")
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "SPEC-1", status: :errored, github_pr_url: "https://github.com/org/repo/pull/7")
  end

  describe "POST resume" do
    it "resumes an errored workflow" do
      post resume_project_workflow_path(project, workflow)

      expect(response).to redirect_to(project_workflow_path(project, workflow))
      expect(flash[:notice]).to eq("Workflow resumed.")
      expect(workflow.reload).to be_reviewing
      expect(workflow.current_stage.stage_runs.pluck(:action)).to eq(%w[resumed])
    end

    it "refuses a workflow that is not errored" do
      workflow.update!(status: :implementing)
      post resume_project_workflow_path(project, workflow)

      expect(response).to redirect_to(project_workflow_path(project, workflow))
      expect(flash[:alert]).to eq("Workflow is not errored.")
      expect(workflow.reload).to be_implementing
    end
  end

  describe "POST rollback_to_review" do
    before { workflow.update!(status: :done) }

    it "rolls a done workflow with a PR back to review" do
      post rollback_to_review_project_workflow_path(project, workflow)

      expect(response).to redirect_to(project_workflow_path(project, workflow))
      expect(flash[:notice]).to eq("Workflow rolled back to review.")
      expect(workflow.reload).to be_reviewing
      expect(workflow.current_stage.stage_runs.pluck(:action)).to eq(%w[rolled_back_to_review])
    end

    it "refuses without a pull request" do
      workflow.update!(github_pr_url: nil)
      post rollback_to_review_project_workflow_path(project, workflow)

      expect(flash[:alert]).to eq("Only done workflows with a pull request can be rolled back.")
      expect(workflow.reload).to be_done
    end
  end

  describe "POST start" do
    it "starts a pending workflow" do
      workflow.update!(status: :pending)
      post start_project_workflow_path(project, workflow)

      expect(flash[:notice]).to eq("Workflow started.")
      expect(workflow.reload).to be_implementing
    end

    it "redirects back to the project list with the status filter kept" do
      workflow.update!(status: :pending)
      post start_project_workflow_path(project, workflow, status: "pending")

      expect(response).to redirect_to(project_path(project, status: "pending"))
    end
  end
end
