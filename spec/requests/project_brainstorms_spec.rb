require "rails_helper"

RSpec.describe "Project brainstorms", type: :request do
  let_personal_project("project-brainstorms-request-spec", brainstorm_goal: "Ship it")
  let(:state_dir) { Brainstorm::Planner::ROOT.join(project.id.to_s) }

  before { allow(AiCli::Runner).to receive(:start).and_return(42_424) }
  after { FileUtils.remove_entry(state_dir) if state_dir.exist? }

  describe "POST brainstorm" do
    it_behaves_like "a manual start action" do
      let(:perform_request) { -> { post brainstorm_project_path(project) } }
      let(:make_blocked) { -> { project.update_columns(brainstorm_goal: nil) } }
      let(:make_running) do
        -> {
          FileUtils.mkdir_p(state_dir)
          state_dir.join("pid").write("999")
          allow(AiCli::Runner).to receive(:poll).and_return(:running)
        }
      end
      let(:make_failing) do
        -> { allow(AiCli::Runner).to receive(:start).and_raise(AiCli::CommandError, "claude exploded") }
      end
      let(:blocked_alert) { "Brainstorm blocked: no goal set" }
      let(:started_notice) { "Agent is brainstorming workflows. They appear within the hour after it finishes." }
      let(:running_alert) { "A brainstorm is already running for this project." }
      let(:failed_alert) { "Brainstorm failed: claude exploded" }
    end

    it "skips while workflows are pending" do
      2.times { build_task_workflow(project) }

      post brainstorm_project_path(project)

      expect(flash[:alert]).to eq("Brainstorm skipped: 2 workflow(s) still pending; start or delete them first.")
    end

    it "records the run time when a brainstorm starts" do
      post brainstorm_project_path(project)

      expect(project.reload.brainstorm_last_run_at).to be_present
    end
  end
end
