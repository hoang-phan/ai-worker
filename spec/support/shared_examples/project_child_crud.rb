# Shared examples for controllers built on ProjectChildCrud (project-nested
# new/edit/create/update/destroy). Include from a request spec that defines
# `project` (e.g. via let_jira_project) and these lets:
#
#   model_class          - the child model (JiraSync)
#   param_key            - params root key (:jira_sync)
#   flash_label          - "Jira sync" (-> "Jira sync created." etc.)
#   child_collection     - project.jira_syncs
#   record               - an existing child of `project`, with `original_attributes`
#   other_record         - a second child of `project` (must not be touched by destroy)
#   foreign_record       - a child of a different project
#   new_path, create_path, edit_path, member_path (given `record`), foreign_edit_path
#   valid_params / created_lookup / created_attributes
#   protected_params / protected_lookup / protected_expectations
#   update_params / updated_attributes / original_attributes
#   invalid_create_params / invalid_update_params
#
# Optional: `invalid_setup` - a lambda run before the invalid examples, for models
# whose validations cannot be tripped with params alone.
RSpec.shared_examples "project child CRUD" do
  let(:invalid_setup) { -> { } }

  describe "GET new and edit" do
    it "renders the forms" do
      get new_path
      expect(response).to have_http_status(:ok)

      get edit_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST create" do
    it "creates a record on the project and redirects with a notice" do
      expect {
        post create_path, params: { param_key => valid_params }
      }.to change(child_collection, :count).by(1)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("#{flash_label} created.")
      expect(created_lookup).to have_attributes(created_attributes)
    end

    it "re-renders the form with 422 when invalid" do
      invalid_setup.call

      expect {
        post create_path, params: { param_key => invalid_create_params }
      }.not_to change(model_class, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Nokogiri::HTML(response.body).at_css("form")).to be_present
    end

    it "ignores protected attributes" do
      post create_path, params: { param_key => protected_params }

      expect(protected_lookup).to have_attributes(protected_expectations)
    end
  end

  describe "PATCH update" do
    it "updates the record and redirects with a notice" do
      patch member_path, params: { param_key => update_params }

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("#{flash_label} updated.")
      expect(record.reload).to have_attributes(updated_attributes)
    end

    it "re-renders with 422 and leaves the record unchanged when invalid" do
      record
      invalid_setup.call

      patch member_path, params: { param_key => invalid_update_params }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(record.reload).to have_attributes(original_attributes)
    end
  end

  describe "DELETE destroy" do
    it "removes only the requested record" do
      record.id
      other = other_record

      expect { delete member_path }.to change(model_class, :count).by(-1)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq("#{flash_label} deleted.")
      expect(model_class).not_to exist(record.id)
      expect(model_class).to exist(other.id)
    end
  end

  it "returns 404 for a record belonging to another project" do
    get foreign_edit_path

    expect(response).to have_http_status(:not_found)
  end
end
