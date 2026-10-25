require "rails_helper"

RSpec.describe "Project brainstorms", type: :request do
  let_jira_project("projects-request-spec")

  describe "POST brainstorm" do
    let_tmpdir(:state_root, "projects-request-state")
    let(:planner) { Brainstorm::Planner.new(project, root: state_root) }

    before do
      allow(planner).to receive_messages(blockers: [], queued_count: 0, start: true)
      allow(Brainstorm::Planner).to receive(:new).and_return(planner)
    end

    it_behaves_like "a manual start action" do
      let(:perform_request) { -> { post brainstorm_project_path(project) } }
      let(:starter) { planner }
      let(:blockers_owner) { planner }
      let(:blocked_blockers) { [ "brainstorm is off" ] }
      let(:blocked_alert) { "Brainstorm blocked: brainstorm is off" }
      let(:started_notice) { "Agent is brainstorming workflows. They appear within the hour after it finishes." }
      let(:running_alert) { "A brainstorm is already running for this project." }
      let(:start_error) { AiCli::CommandError.new("claude exploded") }
      let(:failed_alert) { "Brainstorm failed: claude exploded" }
    end

    it "skips while workflows are pending" do
      allow(planner).to receive(:queued_count).and_return(2)

      post brainstorm_project_path(project)

      expect(flash[:alert]).to eq("Brainstorm skipped: 2 workflow(s) still pending; start or delete them first.")
      expect(planner).not_to have_received(:start)
    end

    it "records the run time when a brainstorm starts" do
      post brainstorm_project_path(project)

      expect(project.reload.brainstorm_last_run_at).to be_present
    end
  end
end
