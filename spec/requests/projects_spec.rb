require "rails_helper"

RSpec.describe "Projects", type: :request do
  let(:local_directory) { Dir.mktmpdir("projects-request-spec") }
  let(:project) { Project.create!(name: "Spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  describe "GET show status filter" do
    it "lists only workflows with the chosen status" do
      project.workflows.create!(jira_ticket: "SPEC-1", branch_name: "b1", github_reviewer: "r", status: :done)
      project.workflows.create!(jira_ticket: "SPEC-2", branch_name: "b2", github_reviewer: "r", status: :pending)
      get project_path(project, status: "pending")

      expect(response.body).to include("SPEC-2")
      expect(response.body).not_to include("SPEC-1")
    end
  end

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

  describe "agent lessons" do
    it "shows an editable textarea and saves it" do
      project.update!(agent_lessons: "Use partial A")

      get edit_project_path(project)
      expect(response.body).to include('name="project[agent_lessons]"', "Use partial A")

      patch project_path(project), params: { project: { agent_lessons: "Use partial A\nPrefer services" } }

      expect(project.reload.agent_lessons).to eq("Use partial A\nPrefer services")
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

  describe "GET show" do
    it "keeps workflow rows compact and uses accessible icon controls for PRs and editing" do
      workflow = project.workflows.create!(jira_ticket: "COMPACT-1", branch_name: "hidden-branch", github_reviewer: "someone", github_pr_url: "https://github.com/org/repo/pull/1")

      get project_path(project)

      expect(response.body).to include('class="workflow-table"', 'aria-label="Open pull request for COMPACT-1"', 'aria-label="Edit COMPACT-1"')
      expect(response.body).not_to include("Current stage", "<th>Branch</th>", "hidden-branch", ">View PR<", ">Edit<")
    end

    it "shows time-log status and makes only unlogged tickets selectable by the header checkbox" do
      logged = project.workflows.create!(jira_ticket: "SPEC-1", branch_name: "spec-1", github_reviewer: "someone")
      unlogged = project.workflows.create!(jira_ticket: "SPEC-2", branch_name: "spec-2", github_reviewer: "someone")
      TimeLog.create!(ticket_key: "SPEC-1", jira_worklog_id: "1", started_at: Time.current, seconds: 3600)

      get project_path(project)

      unlogged_checkbox = response.body.match(/<input[^>]*value="#{unlogged.id}"[^>]*>/)[0]
      logged_checkbox = response.body.match(/<input[^>]*value="#{logged.id}"[^>]*>/)[0]

      expect(response.body).to include("1 h</span>", "Not logged", 'aria-label="Select all tickets without logged time"')
      expect(unlogged_checkbox).to include('data-select-all-target="row"')
      expect(logged_checkbox).not_to include("data-select-all-target")
    end

    it "renders the Jira and Bugsnag sync sections for a jira project" do
      project.jira_syncs.create!(jira_project: "SPEC")
      project.bugsnag_syncs.create!(bugsnag_project: "spec-app", jira_project: "SPEC", last_synced_at: 2.hours.ago)

      get project_path(project)

      expect(response.body).to include("Jira syncs", "Bugsnag triage", "never", "about 2 hours ago")
    end

    it "renders the brainstorm section for a personal project" do
      personal = Project.create!(name: "Personal spec", kind: :personal, local_directory: local_directory, brainstorm_enabled: true, brainstorm_goal: "Ship it", brainstorm_last_run_at: 3.days.ago)

      get project_path(personal)

      expect(response.body).to include("Brainstorm", "3 days ago")
      expect(response.body).not_to include("Jira syncs")
    end

    it "says never for a brainstorm that has not run" do
      personal = Project.create!(name: "Personal spec", kind: :personal, local_directory: local_directory, brainstorm_enabled: true, brainstorm_goal: "Ship it")

      get project_path(personal)

      expect(response.body).to include("Brainstorm", "never")
    end
  end
end
