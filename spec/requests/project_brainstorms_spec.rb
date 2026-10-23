require "rails_helper"

RSpec.describe "Project brainstorms", type: :request do
  let_tmpdir(:local_directory, "projects-request-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }

  describe "POST brainstorm" do
    let_tmpdir(:state_root, "projects-request-state")
    let(:planner) { Brainstorm::Planner.new(project, root: state_root) }

    before do
      allow(planner).to receive_messages(blockers: [], queued_count: 0, start: true)
      allow(Brainstorm::Planner).to receive(:new).and_return(planner)
    end

    it "reports the blockers" do
      allow(planner).to receive(:blockers).and_return([ "brainstorm is off" ])

      post brainstorm_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq("Brainstorm blocked: brainstorm is off")
      expect(planner).not_to have_received(:start)
    end

    it "skips while workflows are pending" do
      allow(planner).to receive(:queued_count).and_return(2)

      post brainstorm_project_path(project)

      expect(flash[:alert]).to eq("Brainstorm skipped: 2 workflow(s) still pending; start or delete them first.")
      expect(planner).not_to have_received(:start)
    end

    it "starts a brainstorm and records the run time" do
      post brainstorm_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Agent is brainstorming workflows. They appear within the hour after it finishes.")
      expect(project.reload.brainstorm_last_run_at).to be_present
    end

    it "says when a brainstorm is already running" do
      allow(planner).to receive(:start).and_return(false)

      post brainstorm_project_path(project)

      expect(flash[:alert]).to eq("A brainstorm is already running for this project.")
    end

    it "reports a failed start" do
      allow(planner).to receive(:start).and_raise(AiCli::CommandError, "claude exploded")

      post brainstorm_project_path(project)

      expect(flash[:alert]).to eq("Brainstorm failed: claude exploded")
    end
  end
end
