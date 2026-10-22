require "rails_helper"

RSpec.describe "Workflows", type: :request do
  include ActiveJob::TestHelper

  let(:local_directory) { Dir.mktmpdir("workflows-request-spec") }
  let(:project) { Project.create!(name: "Spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }
  let(:workflow) do
    project.workflows.create!(jira_ticket: "SPEC-1", branch_name: "spec-1", github_reviewer: "someone", status: :errored,
                              github_pr_url: "https://github.com/org/repo/pull/7")
  end

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  describe "unknown project" do
    it "404s for a nested route" do
      get project_workflow_path(project_id: 0, id: 0)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET show" do
    it "renders the stages table and stage run history" do
      workflow.stages.first.stage_runs.create!(action: "started", output: "Started the implementation")

      get project_workflow_path(project, workflow)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h2>Stages</h2>", "<h2>Stage run history</h2>", "Started the implementation")
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

  describe "POST clone" do
    it "refuses a non-runbook" do
      post clone_project_workflow_path(project, workflow)

      expect(response).to redirect_to(project_workflow_path(project, workflow))
      expect(flash[:alert]).to eq("Only runbooks can be cloned.")
    end

    it "clones a runbook and opens the copy for editing" do
      runbook = project.workflows.create!(kind: :runbook)
      runbook.stages.create!(stage_type: :runbook_step, name: "Build", position: 1)

      expect { post clone_project_workflow_path(project, runbook) }.to change { project.workflows.count }.by(1)

      copy = project.workflows.order(:id).last
      expect(response).to redirect_to(edit_project_workflow_path(project, copy))
      expect(flash[:notice]).to eq("Cloned with 1 stages. Check the variables, then Start.")
    end
  end

  describe "POST move" do
    let!(:first) { project.workflows.create!(jira_ticket: "A-1", branch_name: "a-1", github_reviewer: "x", position: 1) }
    let!(:second) { project.workflows.create!(jira_ticket: "A-2", branch_name: "a-2", github_reviewer: "x", position: 1) }
    let!(:third) { project.workflows.create!(jira_ticket: "A-3", branch_name: "a-3", github_reviewer: "x", position: 3) }

    it "moves a workflow up, even when positions were duplicated" do
      post move_project_workflow_path(project, third, direction: "up")

      expect(response).to redirect_to(project_path(project))
      expect(project.workflows.order(:position).pluck(:id)).to eq([first.id, third.id, second.id])
    end

    it "moves a workflow down" do
      post move_project_workflow_path(project, first, direction: "down")

      expect(project.workflows.order(:position).pluck(:id)).to eq([second.id, first.id, third.id])
    end

    it "leaves the order alone at the ends" do
      post move_project_workflow_path(project, first, direction: "up")

      expect(project.workflows.order(:position).pluck(:id)).to eq([first.id, second.id, third.id])
    end

    it "rejects an unknown direction" do
      post move_project_workflow_path(project, first, direction: "sideways")

      expect(flash[:alert]).to eq("Unknown direction.")
    end
  end

  describe "POST resume" do
    it "resumes an errored workflow" do
      post resume_project_workflow_path(project, workflow)

      expect(response).to redirect_to(project_workflow_path(project, workflow))
      expect(flash[:notice]).to eq("Workflow resumed.")
      expect(workflow.reload).to be_reviewing
      expect(workflow.current_stage.stage_runs.pluck(:action)).to eq(%w[resumed])
    end

    it "refuses a workflow that is not errored" do
      workflow.update!(status: :implementing)
      post resume_project_workflow_path(project, workflow)

      expect(response).to redirect_to(project_workflow_path(project, workflow))
      expect(flash[:alert]).to eq("Workflow is not errored.")
      expect(workflow.reload).to be_implementing
    end
  end

  describe "POST rollback_to_review" do
    before { workflow.update!(status: :done) }

    it "rolls a done workflow with a PR back to review" do
      post rollback_to_review_project_workflow_path(project, workflow)

      expect(response).to redirect_to(project_workflow_path(project, workflow))
      expect(flash[:notice]).to eq("Workflow rolled back to review.")
      expect(workflow.reload).to be_reviewing
      expect(workflow.current_stage.stage_runs.pluck(:action)).to eq(%w[rolled_back_to_review])
    end

    it "refuses without a pull request" do
      workflow.update!(github_pr_url: nil)
      post rollback_to_review_project_workflow_path(project, workflow)

      expect(flash[:alert]).to eq("Only done workflows with a pull request can be rolled back.")
      expect(workflow.reload).to be_done
    end
  end

  describe "POST run_stage" do
    let(:runbook) { project.workflows.create!(kind: :runbook, status: :implementing) }

    it "flags auto_run and enqueues the scheduler job" do
      expect { post run_stage_project_workflow_path(project, runbook) }.to have_enqueued_job(WorkflowSchedulerJob).with(runbook.id)

      expect(flash[:notice]).to eq("Running stage.")
      expect(runbook.reload.auto_run).to be true
    end

    it "refuses and enqueues nothing while processing" do
      runbook.update!(processing: true)
      expect { post run_stage_project_workflow_path(project, runbook) }.not_to have_enqueued_job(WorkflowSchedulerJob)

      expect(flash[:alert]).to eq("Workflow has no stage ready to run.")
    end
  end

  describe "POST start" do
    it "starts a pending workflow" do
      workflow.update!(status: :pending)
      post start_project_workflow_path(project, workflow)

      expect(flash[:notice]).to eq("Workflow started.")
      expect(workflow.reload).to be_implementing
    end
  end

  describe "POST log_time" do
    let(:client) { instance_double(Jira::WorklogClient, add_worklog: "10001", set_original_estimate_if_blank: true, keys_with_my_worklogs_since: []) }

    before do
      project.update!(jira_base_url: "https://example.atlassian.net")
      allow(Jira::WorklogClient).to receive(:new).and_return(client)
    end

    it "logs the preset hours on each selected workflow" do
      other = project.workflows.create!(jira_ticket: "https://example.atlassian.net/browse/SPEC-2", branch_name: "spec-2", github_reviewer: "x")

      expect {
        post log_time_project_workflows_path(project), params: { workflow_ids: [ workflow.id, other.id ], hours: "1.5" }
      }.to change(TimeLog, :count).by(2)

      expect(flash[:notice]).to start_with("Logged 1.5 h")
      expect(client).to have_received(:add_worklog).with("SPEC-1", hash_including(seconds: 5400))
      expect(other.time_logs.first.ticket_key).to eq("SPEC-2")
    end

    it "rejects hours outside the presets" do
      expect {
        post log_time_project_workflows_path(project), params: { workflow_ids: [ workflow.id ], hours: "9" }
      }.not_to change(TimeLog, :count)
      expect(flash[:alert]).to include("Pick one of")
    end

    it "records nothing when Jira rejects the worklog" do
      allow(client).to receive(:add_worklog).and_raise(Jira::WorklogError, "Jira worklog for SPEC-1 failed (HTTP 400)")

      expect {
        post log_time_project_workflows_path(project), params: { workflow_ids: [ workflow.id ], hours: "1" }
      }.not_to change(TimeLog, :count)
      expect(flash[:alert]).to include("HTTP 400")
    end
  end
end
