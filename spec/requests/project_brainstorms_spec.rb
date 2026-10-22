require "rails_helper"

RSpec.describe "Project brainstorms", type: :request do
  let(:local_directory) { Dir.mktmpdir("projects-request-spec") }
  let(:project) { Project.create!(name: "Spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  describe "POST brainstorm" do
    let(:state_root) { Dir.mktmpdir("projects-request-state") }
    let(:planner) { Brainstorm::Planner.new(project, root: state_root) }

    after { FileUtils.remove_entry(state_root) if state_root.start_with?(Dir.tmpdir) && File.exist?(state_root) }

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
