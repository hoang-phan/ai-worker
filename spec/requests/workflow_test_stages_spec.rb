require "rails_helper"

RSpec.describe "WorkflowTestStages", type: :request do
  let_jira_project("workflow-test-stages-request-spec")
  let(:workflow) { build_jira_workflow(project, status: :pending) }

  describe "POST test_stage" do
    it "adds the stage when the project has the credentials" do
      project.update!(local_url: "http://localhost:3000", local_username: "u", local_password: "p")

      post test_stage_project_workflow_path(project, workflow, stage_type: "local_test")

      expect(response).to redirect_to(project_workflow_path(project, workflow))
      expect(flash[:notice]).to eq("Stage added.")
      expect(workflow.stages.pluck(:stage_type)).to include("local_test")
    end

    it "refuses when the project has no credentials" do
      post test_stage_project_workflow_path(project, workflow, stage_type: "local_test")

      expect(response).to redirect_to(project_workflow_path(project, workflow))
      expect(flash[:alert]).to match(/can't be added/)
      expect(workflow.stages.pluck(:stage_type)).not_to include("local_test")
    end
  end
end
