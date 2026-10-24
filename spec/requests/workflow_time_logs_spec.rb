require "rails_helper"

RSpec.describe "WorkflowTimeLogs", type: :request do
  let_jira_project("workflow-time-logs-request-spec")
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "SPEC-1", status: :errored, github_pr_url: "https://github.com/org/repo/pull/7")
  end

  describe "POST log_time" do
    let(:client) { instance_double(Jira::WorklogClient, add_worklog: "10001", set_original_estimate_if_blank: true, keys_with_my_worklogs_since: []) }

    before do
      project.update!(jira_base_url: "https://example.atlassian.net")
      allow(Jira::WorklogClient).to receive(:new).and_return(client)
    end

    it "logs the preset hours on each selected workflow" do
      other = build_jira_workflow(project, jira_ticket: "https://example.atlassian.net/browse/SPEC-2")

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
