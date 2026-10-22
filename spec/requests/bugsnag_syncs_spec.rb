require "rails_helper"

RSpec.describe "BugsnagSyncs", type: :request do
  let(:local_directory) { Dir.mktmpdir("bugsnag-syncs-request-spec") }
  let(:project) { Project.create!(name: "Spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }
  let(:bugsnag_sync) { project.bugsnag_syncs.create!(bugsnag_project: "spec-app", jira_project: "SPEC") }
  let(:triager) { instance_double(Bugsnag::Triager, blockers: [], start: true) }

  before { allow(Bugsnag::Triager).to receive(:new).and_return(triager) }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  describe "POST create" do
    it "re-renders the error summary when invalid" do
      expect {
        post project_bugsnag_syncs_path(project), params: { bugsnag_sync: { bugsnag_project: "", jira_project: "", min_events: 0, max_tickets: 0 } }
      }.not_to change(BugsnagSync, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      summary = Nokogiri::HTML(response.body).at_css(".error-summary").text
      expect(summary).to include("prevented this sync from saving", "Bugsnag project can't be blank")
    end
  end

  describe "POST run" do
    it "reports the blockers" do
      allow(triager).to receive(:blockers).and_return([ "no token" ])

      post run_project_bugsnag_sync_path(project, bugsnag_sync)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq("Bugsnag sync blocked: no token")
      expect(triager).not_to have_received(:start)
    end

    it "starts the triage" do
      post run_project_bugsnag_sync_path(project, bugsnag_sync)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Agent is triaging Bugsnag errors into Jira. The result shows here when it finishes.")
    end

    it "says when a triage is already running" do
      allow(triager).to receive(:start).and_return(false)

      post run_project_bugsnag_sync_path(project, bugsnag_sync)

      expect(flash[:alert]).to eq("A Bugsnag triage is already running for this sync.")
    end

    it "reports a failed start" do
      allow(triager).to receive(:start).and_raise(Bugsnag::FetchError, "bad token")

      post run_project_bugsnag_sync_path(project, bugsnag_sync)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq("Bugsnag sync failed: bad token")
    end
  end
end
