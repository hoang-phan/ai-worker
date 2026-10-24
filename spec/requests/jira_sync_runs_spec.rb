require "rails_helper"

RSpec.describe "JiraSyncRuns", type: :request do
  let_jira_project("jira-sync-runs-request-spec")
  let(:jira_sync) { project.jira_syncs.create!(jira_project: "SPEC") }
  let(:fetcher) { instance_double(Jira::AgentFetcher, start: true) }
  let(:sync) { instance_double(Jira::TicketSync, blockers: [], fetcher: fetcher) }

  before { allow(Jira::TicketSync).to receive(:new).and_return(sync) }
  describe "POST create" do
    it "reports the blockers" do
      allow(sync).to receive(:blockers).and_return([ "no base url" ])

      post run_project_jira_sync_path(project, jira_sync)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq("Jira sync blocked: no base url")
      expect(fetcher).not_to have_received(:start)
    end

    it "starts the fetch" do
      post run_project_jira_sync_path(project, jira_sync)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Asking the agent to fetch your Jira tickets. Workflows appear within a minute or two of it finishing.")
    end

    it "says when a fetch is already running" do
      allow(fetcher).to receive(:start).and_return(false)

      post run_project_jira_sync_path(project, jira_sync)

      expect(flash[:alert]).to eq("A Jira fetch is already running for this sync.")
    end

    it "reports a failed start" do
      allow(fetcher).to receive(:start).and_raise(Jira::FetchError, "bad token")

      post run_project_jira_sync_path(project, jira_sync)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq("Jira sync failed: bad token")
    end
  end
end
