require "rails_helper"

RSpec.describe "BugsnagSyncs", type: :request do
  let_jira_project("bugsnag-syncs-request-spec")
  let(:bugsnag_sync) { project.bugsnag_syncs.create!(bugsnag_project: "web", jira_project: "APP") }

  it_behaves_like "project child CRUD" do
    let(:model_class) { BugsnagSync }
    let(:param_key) { :bugsnag_sync }
    let(:flash_label) { "Bugsnag sync" }
    let(:child_collection) { project.bugsnag_syncs }
    let(:record) { bugsnag_sync }
    let(:other_record) { project.bugsnag_syncs.create!(bugsnag_project: "other", jira_project: "APP") }
    let(:foreign_record) do
      build_jira_project(local_directory: local_directory)
        .bugsnag_syncs.create!(bugsnag_project: "foreign", jira_project: "APP")
    end

    let(:new_path) { new_project_bugsnag_sync_path(project) }
    let(:create_path) { project_bugsnag_syncs_path(project) }
    let(:edit_path) { edit_project_bugsnag_sync_path(project, record) }
    let(:member_path) { project_bugsnag_sync_path(project, record) }
    let(:foreign_edit_path) { edit_project_bugsnag_sync_path(project, foreign_record) }

    let(:valid_params) do
      { bugsnag_project: "api", jira_project: "PLATFORM", min_events: 10, max_tickets: 4, auto_sync: "1" }
    end
    let(:created_lookup) { project.bugsnag_syncs.find_by!(bugsnag_project: "api") }
    let(:created_attributes) { { jira_project: "PLATFORM", min_events: 10, max_tickets: 4, auto_sync: true } }

    let(:protected_params) do
      { bugsnag_project: "api", jira_project: "PLATFORM", last_result: "forced", ledger: { "123" => "APP-1" } }
    end
    let(:protected_lookup) { project.bugsnag_syncs.find_by!(bugsnag_project: "api") }
    let(:protected_expectations) { { last_result: nil, ledger: {} } }

    let(:update_params) do
      { bugsnag_project: "worker", jira_project: "OPS", min_events: 8, max_tickets: 2, auto_sync: "1" }
    end
    let(:updated_attributes) do
      { bugsnag_project: "worker", jira_project: "OPS", min_events: 8, max_tickets: 2, auto_sync: true }
    end
    let(:original_attributes) { { bugsnag_project: "web", jira_project: "APP", min_events: 5 } }

    let(:invalid_create_params) { { bugsnag_project: "", jira_project: "", min_events: 0, max_tickets: 0 } }
    let(:invalid_update_params) { { bugsnag_project: "", min_events: 0 } }
  end

  describe "POST create" do
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
  end
end
