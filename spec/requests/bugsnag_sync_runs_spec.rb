require "rails_helper"

RSpec.describe "BugsnagSyncRuns", type: :request do
  let_jira_project("bugsnag-sync-runs-request-spec", jira_base_url: "https://acme.atlassian.net")
  let(:bugsnag_sync) { project.bugsnag_syncs.create!(bugsnag_project: "spec-app", jira_project: "SPEC") }
  let(:state_dir) { Bugsnag::Triager::ROOT.join(bugsnag_sync.id.to_s) }

  before { allow(AiCli::Runner).to receive(:start).and_return(42_424) }
  after { FileUtils.remove_entry(state_dir) if state_dir.exist? }

  describe "POST create" do
    it_behaves_like "a manual start action" do
      let(:perform_request) { -> { post run_project_bugsnag_sync_path(project, bugsnag_sync) } }
      let(:make_blocked) { -> { project.update_columns(jira_base_url: nil) } }
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
      let(:blocked_alert) { "Bugsnag sync blocked: Jira site URL is not set" }
      let(:started_notice) { "Agent is triaging Bugsnag errors into Jira. The result shows here when it finishes." }
      let(:running_alert) { "A Bugsnag triage is already running for this sync." }
      let(:failed_alert) { "Bugsnag sync failed: claude exploded" }
    end
  end
end
