require "rails_helper"

RSpec.describe "WorkflowImages", type: :request do
  let_tmpdir(:local_directory, "workflow-images-request-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) { build_jira_workflow(project, jira_ticket: "SPEC-1", status: :pending) }

  describe "DELETE image" do
    it "removes the image and redirects to the edit form" do
      delete image_project_workflow_path(project, workflow, name: "missing.png")

      expect(response).to redirect_to(edit_project_workflow_path(project, workflow))
      expect(flash[:notice]).to eq("Image removed.")
    end

    it "404s for an unknown project" do
      delete image_project_workflow_path(project_id: 0, id: 0, name: "a.png")

      expect(response).to have_http_status(:not_found)
    end
  end
end
