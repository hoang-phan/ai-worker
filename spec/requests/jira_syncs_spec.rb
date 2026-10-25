require "rails_helper"

RSpec.describe "JiraSyncs", type: :request do
  let_jira_project("jira-syncs-request-spec")
  let(:jira_sync) { project.jira_syncs.create!(jira_project: "APP", parent_ticket: "APP-1") }

  # JiraSync has no validations, so trip one for the 422 examples. The rule is
  # removed again after the example so other specs never see it.
  let(:force_invalid_rule) { ->(record) { record.errors.add(:base, "forced invalid") } }
  let(:force_invalid) do
    lambda do
      JiraSync.validate(force_invalid_rule)
      @invalid_rule_installed = true
    end
  end
  after { JiraSync.skip_callback(:validate, force_invalid_rule) if @invalid_rule_installed }

  it_behaves_like "project child CRUD" do
    let(:model_class) { JiraSync }
    let(:param_key) { :jira_sync }
    let(:flash_label) { "Jira sync" }
    let(:child_collection) { project.jira_syncs }
    let(:record) { jira_sync }
    let(:other_record) { project.jira_syncs.create!(jira_project: "OTHER") }
    let(:foreign_record) do
      build_jira_project(local_directory: local_directory).jira_syncs.create!(jira_project: "FOREIGN")
    end

    let(:new_path) { new_project_jira_sync_path(project) }
    let(:create_path) { project_jira_syncs_path(project) }
    let(:edit_path) { edit_project_jira_sync_path(project, record) }
    let(:member_path) { project_jira_sync_path(project, record) }
    let(:foreign_edit_path) { edit_project_jira_sync_path(project, foreign_record) }

    let(:valid_params) { { jira_project: "PLATFORM", parent_ticket: "PLATFORM-9", auto_sync: "1" } }
    let(:created_lookup) { project.jira_syncs.find_by!(jira_project: "PLATFORM") }
    let(:created_attributes) { { parent_ticket: "PLATFORM-9", auto_sync: true } }

    let(:protected_params) do
      { jira_project: "PLATFORM", last_result: "forced", last_synced_at: Time.current.iso8601 }
    end
    let(:protected_lookup) { project.jira_syncs.find_by!(jira_project: "PLATFORM") }
    let(:protected_expectations) { { last_result: nil, last_synced_at: nil } }

    let(:update_params) { { jira_project: "OPS", parent_ticket: "OPS-2", auto_sync: "1" } }
    let(:updated_attributes) { { jira_project: "OPS", parent_ticket: "OPS-2", auto_sync: true } }
    let(:original_attributes) { { jira_project: "APP", parent_ticket: "APP-1" } }

    let(:invalid_create_params) { { jira_project: "PLATFORM" } }
    let(:invalid_update_params) { { jira_project: "OPS" } }
    let(:invalid_setup) { force_invalid }
  end

  describe "POST create" do
    it "allows a blank sync that pulls every assigned ticket" do
      expect {
        post project_jira_syncs_path(project), params: { jira_sync: { jira_project: "", parent_ticket: "" } }
      }.to change(project.jira_syncs, :count).by(1)

      expect(response).to redirect_to(project_path(project))
    end
  end
end
