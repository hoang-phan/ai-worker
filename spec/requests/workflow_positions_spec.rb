require "rails_helper"

RSpec.describe "WorkflowPositions", type: :request do
  include ActiveJob::TestHelper

  let(:local_directory) { Dir.mktmpdir("workflow-positions-request-spec") }
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

  describe "POST move" do
    let!(:first) { project.workflows.create!(jira_ticket: "A-1", branch_name: "a-1", github_reviewer: "x", position: 1) }
    let!(:second) { project.workflows.create!(jira_ticket: "A-2", branch_name: "a-2", github_reviewer: "x", position: 1) }
    let!(:third) { project.workflows.create!(jira_ticket: "A-3", branch_name: "a-3", github_reviewer: "x", position: 3) }

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
