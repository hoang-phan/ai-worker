require "rails_helper"

RSpec.describe "Project Slack syncs", type: :request do
  let_tmpdir(:local_directory, "projects-request-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }

  describe "POST sync_slack" do
    let(:fetcher) { instance_double(Slack::MentionFetcher, start: true) }
    let(:sync) { instance_double(Slack::ReviewSync, blockers: [], fetcher: fetcher) }

    before { allow(Slack::ReviewSync).to receive(:new).and_return(sync) }

    it "reports the blockers" do
      allow(sync).to receive(:blockers).and_return([ "no channel", "no mention" ])

      post sync_slack_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq("Slack sync blocked: no channel; no mention")
      expect(fetcher).not_to have_received(:start)
    end

    it "starts the fetch" do
      post sync_slack_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Asking the agent to look through your Slack mentions. Review workflows appear within a minute or two of it finishing.")
    end

    it "says when a fetch is already running" do
      allow(fetcher).to receive(:start).and_return(false)

      post sync_slack_project_path(project)

      expect(flash[:alert]).to eq("A Slack fetch is already running for this project.")
    end

    it "reports a failed start" do
      allow(fetcher).to receive(:start).and_raise(AiCli::CommandError, "claude exploded")

      post sync_slack_project_path(project)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq("Slack sync failed: claude exploded")
    end
  end
end
