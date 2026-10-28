require "rails_helper"

RSpec.describe "Project dashboard", type: :request do
  let_jira_project("projects-request-spec")

  describe "GET show status filter" do
    it "lists only workflows with the chosen status" do
      build_jira_workflow(project, jira_ticket: "SPEC-1", github_reviewer: "r", status: :done)
      build_jira_workflow(project, jira_ticket: "SPEC-2", github_reviewer: "r", status: :pending)
      get project_path(project, status: "pending")

      expect(response.body).to include("SPEC-2")
      expect(response.body).not_to include("SPEC-1")
    end
  end

  describe "GET show header" do
    it "escapes an HTML-ish repo name" do
      project.update_columns(repo_full_name: "acme/<b>x")
      get project_path(project)

      expect(response.body).to include("acme/&lt;b&gt;x")
      expect(response.body).not_to include("acme/<b>x")
    end
  end

  describe "GET show" do
    it "keeps workflow rows compact and uses accessible icon controls for PRs and editing" do
      workflow = build_jira_workflow(project, jira_ticket: "COMPACT-1", branch_name: "hidden-branch", github_reviewer: "someone", github_pr_url: "https://github.com/org/repo/pull/1")

      get project_path(project)

      expect(response.body).to include('class="workflow-table"', 'aria-label="Open pull request for COMPACT-1"', 'aria-label="Edit COMPACT-1"')
      expect(response.body).not_to include("Current stage", "<th>Branch</th>", "hidden-branch", ">View PR<", ">Edit<")
    end

    it "shows time-log status with a single selection checkbox per row" do
      logged = build_jira_workflow(project, jira_ticket: "SPEC-1", github_reviewer: "someone")
      unlogged = build_jira_workflow(project, jira_ticket: "SPEC-2", github_reviewer: "someone")
      TimeLog.create!(ticket_key: "SPEC-1", jira_worklog_id: "1", started_at: Time.current, seconds: 3600)

      get project_path(project)

      unlogged_checkbox = response.body.match(/<input[^>]*value="#{unlogged.id}"[^>]*>/)[0]
      logged_checkbox = response.body.match(/<input[^>]*value="#{logged.id}"[^>]*>/)[0]

      expect(response.body).to include("1 h</span>", "Not logged", 'id="workflow-selection-form"', "Select all non time logged")
      expect(response.body.scan('name="workflow_ids[]"').size).to eq(2)
      expect(unlogged_checkbox).to include('data-fresh="true"', 'data-log-time="true"')
      expect(logged_checkbox).to include('data-fresh="false"', 'data-log-time="true"')
    end

    it "renders the Jira and Bugsnag sync sections for a jira project" do
      project.jira_syncs.create!(jira_project: "SPEC")
      project.bugsnag_syncs.create!(bugsnag_project: "spec-app", jira_project: "SPEC", last_synced_at: 2.hours.ago)

      get project_path(project)

      expect(response.body).to include("Jira syncs", "Bugsnag triage", "never", "about 2 hours ago")
    end

    it "renders the brainstorm section for a personal project" do
      personal = Project.create!(name: "Personal spec", kind: :personal, local_directory: local_directory, brainstorm_enabled: true, brainstorm_goal: "Ship it", brainstorm_last_run_at: 3.days.ago, brainstorm_last_result: "created 2")

      get project_path(personal)

      expect(Nokogiri::HTML(response.body).text).to include("Brainstorm", "3 days ago · created 2 · 0 pending")
      expect(response.body).not_to include("Jira syncs", "Log time on selected", "Select all non time logged")
    end

    it "renders the workflow empty state" do
      get project_path(project)

      expect(response.body).to include('class="empty-state">No workflows yet. <a href="/projects/')
      expect(response.body).to include('">Create one</a>.</div>')
    end

    it "renders the Slack review last-run summary" do
      project.update!(slack_review_enabled: true, slack_last_synced_at: 2.hours.ago, slack_last_result: "created 1")

      get project_path(project)

      expect(response.body).to include("Slack PR reviews", "about 2 hours ago · created 1")
    end

    it "says never for a brainstorm that has not run" do
      personal = Project.create!(name: "Personal spec", kind: :personal, local_directory: local_directory, brainstorm_enabled: true, brainstorm_goal: "Ship it")

      get project_path(personal)

      expect(response.body).to include("Brainstorm", "never")
    end
  end
end
