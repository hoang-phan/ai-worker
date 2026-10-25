require "rails_helper"

RSpec.describe "BugsnagSyncRuns", type: :request do
  let_jira_project("bugsnag-sync-runs-request-spec")
  let(:bugsnag_sync) { project.bugsnag_syncs.create!(bugsnag_project: "spec-app", jira_project: "SPEC") }
  let(:triager) { instance_double(Bugsnag::Triager, start: true) }
  let(:triage_sync) { instance_double(Bugsnag::TriageSync, blockers: [], triager: triager) }

  before { allow(Bugsnag::TriageSync).to receive(:new).and_return(triage_sync) }

  describe "POST create" do
    it_behaves_like "a manual start action" do
      let(:perform_request) { -> { post run_project_bugsnag_sync_path(project, bugsnag_sync) } }
      let(:starter) { triager }
      let(:blockers_owner) { triage_sync }
      let(:blocked_blockers) { [ "no token" ] }
      let(:blocked_alert) { "Bugsnag sync blocked: no token" }
      let(:started_notice) { "Agent is triaging Bugsnag errors into Jira. The result shows here when it finishes." }
      let(:running_alert) { "A Bugsnag triage is already running for this sync." }
      let(:start_error) { Bugsnag::FetchError.new("bad token") }
      let(:failed_alert) { "Bugsnag sync failed: bad token" }
    end
  end
end
