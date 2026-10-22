require "rails_helper"

RSpec.describe "PromptTemplates", type: :request do
  let(:local_directory) { Dir.mktmpdir("prompt-templates-request-spec") }
  let(:project) { Project.create!(name: "Spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }
  let(:workflow) { project.workflows.create!(jira_ticket: "PT-1", branch_name: "pt-1", github_reviewer: "someone", status: :pending) }
  let!(:template) { PromptTemplate.create!(name: "Spec template", stage_type: :task, body: "Do the thing") }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  describe "GET index" do
    it "lists the templates" do
      get prompt_templates_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Spec template")
    end
  end

  describe "GET show" do
    it "shows the template" do
      get prompt_template_path(template)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Spec template")
    end
  end

  describe "GET new" do
    it "renders the form" do
      get new_prompt_template_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST create" do
    it "creates the template and redirects with a notice" do
      expect {
        post prompt_templates_path, params: { prompt_template: { name: "Created", stage_type: "pr_check", body: "Check it" } }
      }.to change(PromptTemplate, :count).by(1)

      created = PromptTemplate.find_by!(name: "Created")
      expect(response).to redirect_to(prompt_template_path(created))
      expect(flash[:notice]).to eq("Template created.")
    end

    it "re-renders with 422 when the body is blank" do
      expect {
        post prompt_templates_path, params: { prompt_template: { name: "Invalid", stage_type: "task", body: "" } }
      }.not_to change(PromptTemplate, :count)

      expect(response).to have_http_status(422)
      summary = Nokogiri::HTML(response.body).at_css(".error-summary").text
      expect(summary).to include("prevented this template from saving", "Body can't be blank")
    end
  end

  describe "PATCH update" do
    it "updates the template and redirects with a notice" do
      patch prompt_template_path(template), params: { prompt_template: { body: "New body" } }

      expect(response).to redirect_to(prompt_template_path(template))
      expect(flash[:notice]).to eq("Template updated.")
      expect(template.reload.body).to eq("New body")
    end

    it "re-renders with 422 when invalid" do
      patch prompt_template_path(template), params: { prompt_template: { body: "" } }

      expect(response).to have_http_status(422)
      expect(template.reload.body).to eq("Do the thing")
    end
  end

  describe "DELETE destroy" do
    it "deletes the template and nullifies the stages that used it" do
      stage = workflow.stages.create!(stage_type: :task, prompt_template: template)

      expect { delete prompt_template_path(template) }.to change(PromptTemplate, :count).by(-1)

      expect(response).to redirect_to(prompt_templates_path)
      expect(flash[:notice]).to eq("Template deleted.")
      expect(stage.reload.prompt_template_id).to be_nil
    end
  end
end
