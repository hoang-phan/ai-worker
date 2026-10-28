require "rails_helper"

RSpec.describe "JiraSyncRuns", type: :request do
  let_jira_project("jira-sync-runs-request-spec",
                   jira_base_url: "https://acme.atlassian.net",
                   jira_assignee: "me@example.com",
                   default_reviewers: "alice")
  let(:jira_sync) { project.jira_syncs.create!(jira_project: "SPEC") }
  let(:state_dir) { Jira::AgentFetcher::ROOT.join(jira_sync.id.to_s) }

  before { allow(AiCli::Runner).to receive(:start).and_return(42_424) }
  after { FileUtils.remove_entry(state_dir) if state_dir.exist? }

  describe "POST create" do
    it_behaves_like "a manual start action" do
      let(:perform_request) { -> { post run_project_jira_sync_path(project, jira_sync) } }
      let(:make_blocked) { -> { project.update_columns(jira_assignee: nil) } }
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
      let(:blocked_alert) { "Jira sync blocked: assignee is not set" }
      let(:started_notice) { "Asking the agent to fetch your Jira tickets. Workflows appear within a minute or two of it finishing." }
      let(:running_alert) { "A Jira fetch is already running for this sync." }
      let(:failed_alert) { "Jira sync failed: claude exploded" }
    end
  end
end
