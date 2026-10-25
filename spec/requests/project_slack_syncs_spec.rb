require "rails_helper"

RSpec.describe "Project Slack syncs", type: :request do
  let_jira_project("projects-request-spec")

  describe "POST sync_slack" do
    let(:fetcher) { instance_double(Slack::MentionFetcher, start: true) }
    let(:sync) { instance_double(Slack::ReviewSync, blockers: [], fetcher: fetcher) }

    before { allow(Slack::ReviewSync).to receive(:new).and_return(sync) }

    it_behaves_like "a manual start action" do
      let(:perform_request) { -> { post sync_slack_project_path(project) } }
      let(:starter) { fetcher }
      let(:blockers_owner) { sync }
      let(:blocked_blockers) { [ "no channel", "no mention" ] }
      let(:blocked_alert) { "Slack sync blocked: no channel; no mention" }
      let(:started_notice) { "Asking the agent to look through your Slack mentions. Review workflows appear within a minute or two of it finishing." }
      let(:running_alert) { "A Slack fetch is already running for this project." }
      let(:start_error) { AiCli::CommandError.new("claude exploded") }
      let(:failed_alert) { "Slack sync failed: claude exploded" }
    end
  end
end
