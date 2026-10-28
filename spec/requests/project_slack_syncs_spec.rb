require "rails_helper"

RSpec.describe "Project Slack syncs", type: :request do
  let_jira_project("project-slack-syncs-request-spec", slack_mention: "@reviewer")
  let(:state_dir) { Slack::MentionFetcher::ROOT.join(project.id.to_s) }

  before { allow(AiCli::Runner).to receive(:start).and_return(42_424) }
  after { FileUtils.remove_entry(state_dir) if state_dir.exist? }

  describe "POST sync_slack" do
    it_behaves_like "a manual start action" do
      let(:perform_request) { -> { post sync_slack_project_path(project) } }
      let(:make_blocked) { -> { project.update_columns(slack_mention: nil) } }
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
      let(:blocked_alert) { "Slack sync blocked: Slack mention is not set" }
      let(:started_notice) { "Asking the agent to look through your Slack mentions. Review workflows appear within a minute or two of it finishing." }
      let(:running_alert) { "A Slack fetch is already running for this project." }
      let(:failed_alert) { "Slack sync failed: claude exploded" }
    end
  end
end
