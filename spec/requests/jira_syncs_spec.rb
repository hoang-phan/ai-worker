require "rails_helper"

RSpec.describe "JiraSyncs", type: :request do
  let(:local_directory) { Dir.mktmpdir("jira-syncs-request-spec") }
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:jira_sync) { project.jira_syncs.create!(jira_project: "APP", parent_ticket: "APP-1") }

  after do
    FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory)
  end

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
          jira_sync: { jira_project: "PLATFORM", parent_ticket: "PLATFORM-10", auto_sync: "1" }
        }
      }.to change(project.jira_syncs, :count).by(1)

      created = project.jira_syncs.find_by!(jira_project: "PLATFORM")
      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("Jira sync created.")
      expect(created).to have_attributes(parent_ticket: "PLATFORM-10", auto_sync: true)
    end

    it "re-renders the error summary when persistence fails" do
      allow_any_instance_of(JiraSync).to receive(:save) do |sync|
        sync.errors.add(:base, "could not be saved")
        false
      end

      expect {
        post project_jira_syncs_path(project), params: { jira_sync: { jira_project: "APP" } }
      }.not_to change(JiraSync, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      summary = Nokogiri::HTML(response.body).at_css(".error-summary").text
      expect(summary).to include("prevented this sync from saving", "could not be saved")
    end

    it "ignores protected attributes" do
      post project_jira_syncs_path(project), params: {
        jira_sync: { jira_project: "PLATFORM", last_result: "forced" }
      }

      expect(project.jira_syncs.find_by!(jira_project: "PLATFORM").last_result).to be_nil
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

    it "re-renders with 422 and leaves the record unchanged when persistence fails" do
      allow_any_instance_of(JiraSync).to receive(:update) do |sync|
        sync.errors.add(:base, "could not be saved")
        false
      end

      patch project_jira_sync_path(project, jira_sync), params: { jira_sync: { jira_project: "OPS" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(jira_sync.reload).to have_attributes(jira_project: "APP", parent_ticket: "APP-1", auto_sync: false)
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
