require "rails_helper"

RSpec.describe "BugsnagSyncs", type: :request do
  let_tmpdir(:local_directory, "bugsnag-syncs-request-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:bugsnag_sync) { project.bugsnag_syncs.create!(bugsnag_project: "web", jira_project: "APP") }

  describe "GET new and edit" do
    it "renders the forms" do
      get new_project_bugsnag_sync_path(project)
      expect(response).to have_http_status(:ok)

      get edit_project_bugsnag_sync_path(project, bugsnag_sync)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST create" do
    it "creates a sync on the project and redirects with a notice" do
      expect {
        post project_bugsnag_syncs_path(project), params: {
          bugsnag_sync: { bugsnag_project: "api", jira_project: "PLATFORM", min_events: 10, max_tickets: 4, auto_sync: "1" }
        }
      }.to change(project.bugsnag_syncs, :count).by(1)

      created = project.bugsnag_syncs.find_by!(bugsnag_project: "api")
      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Bugsnag sync created.")
      expect(created).to have_attributes(jira_project: "PLATFORM", min_events: 10, max_tickets: 4, auto_sync: true)
    end

    it "re-renders the error summary when invalid" do
      expect {
        post project_bugsnag_syncs_path(project), params: {
          bugsnag_sync: { bugsnag_project: "", jira_project: "", min_events: 0, max_tickets: 0 }
        }
      }.not_to change(BugsnagSync, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      summary = Nokogiri::HTML(response.body).at_css(".error-summary").text
      expect(summary).to include("prevented this sync from saving", "Bugsnag project can't be blank")
    end

    it "ignores protected attributes" do
      post project_bugsnag_syncs_path(project), params: {
        bugsnag_sync: {
          bugsnag_project: "api", jira_project: "PLATFORM", last_result: "forced", ledger: { "123" => "APP-1" }
        }
      }

      created = project.bugsnag_syncs.find_by!(bugsnag_project: "api")
      expect(created).to have_attributes(last_result: nil, ledger: {})
    end
  end

  describe "PATCH update" do
    it "updates the sync and redirects with a notice" do
      patch project_bugsnag_sync_path(project, bugsnag_sync), params: {
        bugsnag_sync: { bugsnag_project: "worker", jira_project: "OPS", min_events: 8, max_tickets: 2, auto_sync: "1" }
      }

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Bugsnag sync updated.")
      expect(bugsnag_sync.reload).to have_attributes(
        bugsnag_project: "worker", jira_project: "OPS", min_events: 8, max_tickets: 2, auto_sync: true
      )
    end

    it "re-renders with 422 and leaves the record unchanged when invalid" do
      patch project_bugsnag_sync_path(project, bugsnag_sync), params: {
        bugsnag_sync: { bugsnag_project: "", min_events: 0 }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(bugsnag_sync.reload).to have_attributes(bugsnag_project: "web", jira_project: "APP", min_events: 5)
    end
  end

  describe "DELETE destroy" do
    it "removes only the requested sync" do
      bugsnag_sync.id
      other_sync = project.bugsnag_syncs.create!(bugsnag_project: "other", jira_project: "APP")

      expect { delete project_bugsnag_sync_path(project, bugsnag_sync) }.to change(BugsnagSync, :count).by(-1)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Bugsnag sync deleted.")
      expect(BugsnagSync).not_to exist(bugsnag_sync.id)
      expect(BugsnagSync).to exist(other_sync.id)
    end
  end

  it "returns 404 for a sync belonging to another project" do
    other_project = build_jira_project(local_directory: local_directory)
    foreign_sync = other_project.bugsnag_syncs.create!(bugsnag_project: "foreign", jira_project: "APP")

    get edit_project_bugsnag_sync_path(project, foreign_sync)

    expect(response).to have_http_status(:not_found)
  end
end
