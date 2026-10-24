require "rails_helper"

RSpec.describe "WorkflowRunbooks", type: :request, active_job_test_adapter: true do
  include ActiveJob::TestHelper

  let_jira_project("workflow-runbooks-request-spec")
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "SPEC-1", status: :errored, github_pr_url: "https://github.com/org/repo/pull/7")
  end

  describe "POST clone" do
    it "refuses a non-runbook" do
      post clone_project_workflow_path(project, workflow)

      expect(response).to redirect_to(project_workflow_path(project, workflow))
      expect(flash[:alert]).to eq("Only runbooks can be cloned.")
    end

    it "clones a runbook and opens the copy for editing" do
      runbook = build_runbook_workflow(project)
      build_runbook_stage(runbook, name: "Build", position: 1)

      expect { post clone_project_workflow_path(project, runbook) }.to change { project.workflows.count }.by(1)

      copy = project.workflows.order(:id).last
      expect(response).to redirect_to(edit_project_workflow_path(project, copy))
      expect(flash[:notice]).to eq("Cloned with 1 stages. Check the variables, then Start.")
    end
  end

  describe "POST run_stage" do
    let(:runbook) { build_runbook_workflow(project, status: :implementing) }

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
end
