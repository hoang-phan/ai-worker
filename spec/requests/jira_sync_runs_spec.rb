require "rails_helper"

RSpec.describe "JiraSyncRuns", type: :request do
  let_jira_project("jira-sync-runs-request-spec")
  let(:jira_sync) { project.jira_syncs.create!(jira_project: "SPEC") }
  let(:fetcher) { instance_double(Jira::AgentFetcher, start: true) }
  let(:sync) { instance_double(Jira::TicketSync, blockers: [], fetcher: fetcher) }

  before { allow(Jira::TicketSync).to receive(:new).and_return(sync) }

  describe "POST create" do
    it_behaves_like "a manual start action" do
      let(:perform_request) { -> { post run_project_jira_sync_path(project, jira_sync) } }
      let(:starter) { fetcher }
      let(:blockers_owner) { sync }
      let(:blocked_blockers) { [ "no base url" ] }
      let(:blocked_alert) { "Jira sync blocked: no base url" }
      let(:started_notice) { "Asking the agent to fetch your Jira tickets. Workflows appear within a minute or two of it finishing." }
      let(:running_alert) { "A Jira fetch is already running for this sync." }
      let(:start_error) { Jira::FetchError.new("bad token") }
      let(:failed_alert) { "Jira sync failed: bad token" }
    end
  end
end
