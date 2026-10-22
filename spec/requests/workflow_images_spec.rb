require "rails_helper"

RSpec.describe "WorkflowImages", type: :request do
  let(:local_directory) { Dir.mktmpdir("workflow-images-request-spec") }
  let(:project) { Project.create!(name: "Spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }
  let(:workflow) { project.workflows.create!(jira_ticket: "SPEC-1", branch_name: "spec-1", github_reviewer: "someone", status: :pending) }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

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
