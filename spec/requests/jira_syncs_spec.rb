require "rails_helper"

RSpec.describe "JiraSyncs", type: :request do
  let_tmpdir(:local_directory, "jira-syncs-request-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:jira_sync) { project.jira_syncs.create!(jira_project: "APP", parent_ticket: "APP-1") }

  describe "GET new and edit" do
    it "renders the forms" do
      get new_project_jira_sync_path(project)
      expect(response).to have_http_status(:ok)

      get edit_project_jira_sync_path(project, jira_sync)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST create" do
    it "creates a sync on the project and redirects with a notice" do
      expect {
        post project_jira_syncs_path(project), params: {
          jira_sync: { jira_project: "PLATFORM", parent_ticket: "PLATFORM-9", auto_sync: "1" }
        }
      }.to change(project.jira_syncs, :count).by(1)

      created = project.jira_syncs.find_by!(jira_project: "PLATFORM")
      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Jira sync created.")
      expect(created).to have_attributes(parent_ticket: "PLATFORM-9", auto_sync: true)
    end

    it "allows a blank sync that pulls every assigned ticket" do
      expect {
        post project_jira_syncs_path(project), params: { jira_sync: { jira_project: "", parent_ticket: "" } }
      }.to change(project.jira_syncs, :count).by(1)

      expect(response).to redirect_to(project_path(project))
    end

    it "re-renders the form with 422 when the sync is invalid" do
      allow_any_instance_of(JiraSync).to receive(:valid?).and_return(false)

      expect {
        post project_jira_syncs_path(project), params: { jira_sync: { jira_project: "PLATFORM" } }
      }.not_to change(JiraSync, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Nokogiri::HTML(response.body).at_css("form")).to be_present
    end

    it "ignores protected attributes" do
      post project_jira_syncs_path(project), params: {
        jira_sync: { jira_project: "PLATFORM", last_result: "forced", last_synced_at: Time.current.iso8601 }
      }

      created = project.jira_syncs.find_by!(jira_project: "PLATFORM")
      expect(created).to have_attributes(last_result: nil, last_synced_at: nil)
    end
  end

  describe "PATCH update" do
    it "updates the sync and redirects with a notice" do
      patch project_jira_sync_path(project, jira_sync), params: {
        jira_sync: { jira_project: "OPS", parent_ticket: "OPS-2", auto_sync: "1" }
      }

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Jira sync updated.")
      expect(jira_sync.reload).to have_attributes(jira_project: "OPS", parent_ticket: "OPS-2", auto_sync: true)
    end

    it "re-renders with 422 and leaves the record unchanged when invalid" do
      jira_sync
      allow_any_instance_of(JiraSync).to receive(:valid?).and_return(false)

      patch project_jira_sync_path(project, jira_sync), params: { jira_sync: { jira_project: "OPS" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(jira_sync.reload).to have_attributes(jira_project: "APP", parent_ticket: "APP-1")
    end
  end

  describe "DELETE destroy" do
    it "removes only the requested sync" do
      jira_sync.id
      other_sync = project.jira_syncs.create!(jira_project: "OTHER")

      expect { delete project_jira_sync_path(project, jira_sync) }.to change(JiraSync, :count).by(-1)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Jira sync deleted.")
      expect(JiraSync).not_to exist(jira_sync.id)
      expect(JiraSync).to exist(other_sync.id)
    end
  end

  it "returns 404 for a sync belonging to another project" do
    other_project = build_jira_project(local_directory: local_directory)
    foreign_sync = other_project.jira_syncs.create!(jira_project: "FOREIGN")

    get edit_project_jira_sync_path(project, foreign_sync)

    expect(response).to have_http_status(:not_found)
  end
end
