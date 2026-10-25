require "rails_helper"

RSpec.describe "Workflows", type: :request, active_job_test_adapter: true do
  include ActiveJob::TestHelper

  let_jira_project("workflows-request-spec")
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "SPEC-1", github_reviewer: "someone", status: :errored, github_pr_url: "https://github.com/org/repo/pull/7")
  end

  describe "unknown project" do
    it "404s for a nested route" do
      get project_workflow_path(project_id: 0, id: 0)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET new / edit forms" do
    it "renders the Jira fields for a development workflow" do
      get edit_project_workflow_path(project, workflow)
      expect(response.body).to include("workflow[jira_ticket]", "workflow[branch_name]", "workflow[github_reviewer]",
                                       "workflow[skills]", "workflow[slack_review_thread_ts]", "workflow[images][]",
                                       "workflow[position]")
      expect(response.body).not_to include("workflow[task_description]")
    end

    it "renders the skills and PR skills textareas as insert targets with skill chips" do
      FileUtils.mkdir_p(File.join(local_directory, ".agents", "skills", "spec-skill"))
      ci_project = build_ci_project(local_directory: local_directory)

      [ new_project_workflow_path(ci_project), edit_project_workflow_path(ci_project, build_ci_workflow(ci_project)) ].each do |path|
        get path

        document = Nokogiri::HTML(response.body)
        %w[workflow_skills workflow_pr_skills].each do |id|
          field = document.at_css(%([data-controller~="skill-insert"].field:has(> ##{id}[data-skill-insert-target="input"])))
          expect(field.at_css('.skill-chip[data-skill="spec-skill"]')).to be_present
        end
      end
    end

    it "omits the PR skills field outside the check / verify loop flow" do
      get new_project_workflow_path(project)
      expect(response.body).to include("workflow[skills]")
      expect(response.body).not_to include("workflow[pr_skills]")
    end

    it "renders the task field for a personal project" do
      personal = build_personal_project
      get new_project_workflow_path(personal)
      expect(response.body).to include("workflow[task_description]", "workflow[images][]")
      expect(response.body).not_to include("workflow[jira_ticket]")
    end

    it "renders the runbook fields with a copy select when a runbook exists" do
      source = build_runbook_workflow(project)
      get new_project_workflow_path(project, kind: "runbook")
      expect(response.body).to include("workflow[variables_text]", "workflow[copy_stages_from_id]", "##{source.id} ")
      expect(response.body).not_to include("workflow[images][]")
    end

    it "omits the copy select without runbooks" do
      get new_project_workflow_path(project, kind: "runbook")
      expect(response.body).to include("workflow[variables_text]")
      expect(response.body).not_to include("workflow[copy_stages_from_id]")
    end
  end

  describe "invalid create and update" do
    it "re-renders the workflow error summary when creating" do
      expect {
        post project_workflows_path(project), params: { workflow: { jira_ticket: "", branch_name: "", github_reviewer: "" } }
      }.not_to change(Workflow, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      summary = Nokogiri::HTML(response.body).at_css(".error-summary").text
      expect(summary).to include("prevented this workflow from saving", "Jira ticket can't be blank")
    end

    it "re-renders the workflow error summary when updating" do
      patch project_workflow_path(project, workflow), params: { workflow: { jira_ticket: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      summary = Nokogiri::HTML(response.body).at_css(".error-summary").text
      expect(summary).to include("prevented this workflow from saving", "Jira ticket can't be blank")
    end
  end

  describe "GET show" do
    it "renders the stages table and stage run history" do
      workflow.stages.first.stage_runs.create!(action: "started", output: "Started the implementation")

      get project_workflow_path(project, workflow)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h2>Stages</h2>", "<h2>Stage run history</h2>", "Started the implementation")
    end

    describe "state-dependent buttons" do
      let(:runbook) { build_runbook_workflow(project, status: :implementing) }

      it "shows Next only for a runbook awaiting Next" do
        get project_workflow_path(project, runbook)
        expect(response.body).not_to include(advance_project_workflow_path(project, runbook))

        runbook.update!(awaiting_next: true)
        get project_workflow_path(project, runbook)
        expect(response.body).to include(advance_project_workflow_path(project, runbook))
      end

      it "shows the rollback button only for a done development workflow with a PR" do
        path = rollback_to_review_project_workflow_path(project, workflow)
        get project_workflow_path(project, workflow)
        expect(response.body).not_to include(path)

        workflow.update!(status: :done)
        get project_workflow_path(project, workflow)
        expect(response.body).to include(path)

        workflow.update!(github_pr_url: nil)
        get project_workflow_path(project, workflow)
        expect(response.body).not_to include(path)
      end
    end
  end

  describe "GET show stage run history" do
    it "lists only this workflow's runs, newest first" do
      stage = workflow.stages.first
      now = Time.current.change(usec: 0)
      stage.stage_runs.create!(action: "started", output: "Older output", created_at: now - 1.hour)
      stage.stage_runs.create!(action: "resumed", output: "Newer output", created_at: now)
      other = build_jira_workflow(project, jira_ticket: "SPEC-2", github_reviewer: "someone", status: :pending)
      other.stages.first.stage_runs.create!(action: "failed", output: "Foreign output")

      get project_workflow_path(project, workflow)

      expect(response.body).to include("Older output", "Newer output")
      expect(response.body).not_to include("Foreign output")
      expect(response.body.index("Newer output")).to be < response.body.index("Older output")
    end

    it "shows the empty state without runs" do
      get project_workflow_path(project, workflow)

      expect(response.body).to include("No stage runs yet.")
    end
  end

  describe "GET show with Jira hours" do
    it "shows the hours mirrored from Jira" do
      workflow.update!(jira_logged_synced_at: 5.minutes.ago)
      TimeLog.create!(ticket_key: "SPEC-1", jira_worklog_id: "1", started_at: Time.current, seconds: 5400)

      get project_workflow_path(project, workflow)

      expect(response.body).to include("1.5 h logged in Jira — synced 5 minutes ago")
    end
  end
end
