require "rails_helper"

RSpec.describe "WorkflowTransitions", type: :request do
  include ActiveJob::TestHelper

  let(:local_directory) { Dir.mktmpdir("workflow-transitions-request-spec") }
  let(:project) { Project.create!(name: "Spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }
  let(:workflow) do
    project.workflows.create!(jira_ticket: "SPEC-1", branch_name: "spec-1", github_reviewer: "someone", status: :errored,
                              github_pr_url: "https://github.com/org/repo/pull/7")
  end

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

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
