require "rails_helper"

RSpec.describe "Projects", type: :request do
  let_jira_project("projects-request-spec")

  describe "GET new and edit" do
    it "renders every optional settings fieldset and preserves saved password placeholders" do
      get new_project_path

      expect(response.body).to include(
        "Jira integration (optional)",
        "UAT test by the agent (optional)",
        "Local test by the agent (optional)",
        "Brainstorm workflows (optional)",
        "Slack PR reviews (optional)",
        "Slack review requests (optional)",
        'name="project[jira_base_url]"',
        'name="project[uat_password]"',
        'name="project[local_url]"',
        'name="project[brainstorm_goal]"',
        'name="project[slack_review_channel]"'
      )

      project.update!(uat_password: "secret")
      get edit_project_path(project)

      expect(response.body).to include('name="project[uat_password]"', 'placeholder="Saved (leave blank to keep)"')
    end
  end

  describe "GET new and edit skills fields" do
    it "renders both skills textareas as insert targets, with skill chips only for a persisted project" do
      get new_project_path

      document = Nokogiri::HTML(response.body)
      %w[project_default_skills project_default_pr_skills].each do |id|
        expect(document.at_css(%([data-controller~="skill-insert"].field > ##{id}[data-skill-insert-target="input"]))).to be_present
      end
      pr_skills_field = document.at_css(%([data-controller~="skill-insert"].field:has(> #project_default_pr_skills)))
      pr_skills_token = pr_skills_field.at_css(".field-hint code")
      expect(pr_skills_token).to be_present
      expect(pr_skills_token.text).to eq("{PR_SKILLS}")
      expect(document.css(".skill-chip")).to be_empty

      FileUtils.mkdir_p(File.join(local_directory, ".agents", "skills", "spec-skill"))
      get edit_project_path(project)

      document = Nokogiri::HTML(response.body)
      %w[project_default_skills project_default_pr_skills].each do |id|
        field = document.at_css(%([data-controller~="skill-insert"].field:has(> ##{id}[data-skill-insert-target="input"])))
        expect(field.at_css('.skill-chip[data-skill="spec-skill"]')).to be_present
      end
    end
  end

  describe "agent lessons" do
    it "shows an editable textarea and saves it" do
      project.update!(agent_lessons: "Use partial A")

      get edit_project_path(project)
      expect(response.body).to include('name="project[agent_lessons]"', "Use partial A")

      patch project_path(project), params: { project: { agent_lessons: "Use partial A\nPrefer services" } }

      expect(project.reload.agent_lessons).to eq("Use partial A\nPrefer services")
    end
  end

  describe "PATCH update passwords" do
    it "keeps saved UAT and local passwords when both submitted values are blank" do
      project.update!(uat_password: "uat secret", local_password: "local secret")

      patch project_path(project), params: { project: { uat_password: "", local_password: "" } }

      expect(project.reload).to have_attributes(uat_password: "uat secret", local_password: "local secret")
    end
  end

  describe "POST create" do
    it "re-renders the error summary when invalid" do
      expect {
        post projects_path, params: { project: { name: "", kind: "jira" } }
      }.not_to change(Project, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      summary = Nokogiri::HTML(response.body).at_css(".error-summary").text
      expect(summary).to include("prevented this project from saving", "Name can't be blank")
    end
  end
end
