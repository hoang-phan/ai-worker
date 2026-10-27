require "rails_helper"

RSpec.describe "WorkflowTimeLogs", type: :request do
  let_jira_project("workflow-time-logs-request-spec")
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "SPEC-1", status: :errored, github_pr_url: "https://github.com/org/repo/pull/7")
  end
  let(:jira_requests) { [] }
  let(:worklog_status) { 201 }

  describe "POST log_time" do
    before do
      project.update!(jira_base_url: "https://example.atlassian.net")
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("JIRA_EMAIL").and_return("test@example.com")
      allow(ENV).to receive(:[]).with("JIRA_ACCESS_TOKEN").and_return("fake-token")
      stub_jira_http
    end

    it "logs the preset hours on each selected workflow" do
      other = build_jira_workflow(project, jira_ticket: "https://example.atlassian.net/browse/SPEC-2")

      expect {
        post log_time_project_workflows_path(project), params: { workflow_ids: [ workflow.id, other.id ], hours: "1.5" }
      }.to change(TimeLog, :count).by(2)

      expect(flash[:notice]).to start_with("Logged 1.5 h")
      expect(JSON.parse(spec1_worklog_post.body)).to include("timeSpentSeconds" => 5400)
      expect(other.time_logs.first.ticket_key).to eq("SPEC-2")
    end

    it "rejects hours outside the presets" do
      expect {
        post log_time_project_workflows_path(project), params: { workflow_ids: [ workflow.id ], hours: "9" }
      }.not_to change(TimeLog, :count)
      expect(flash[:alert]).to include("Pick one of")
    end

    context "when Jira rejects the worklog" do
      let(:worklog_status) { 400 }

      it "records nothing" do
        expect {
          post log_time_project_workflows_path(project), params: { workflow_ids: [ workflow.id ], hours: "1" }
        }.not_to change(TimeLog, :count)
        expect(flash[:alert]).to include("HTTP 400")
      end
    end
  end

  def stub_jira_http
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:request) do |req|
      jira_requests << req
      jira_response_for(req)
    end
  end

  def http_response(code, body = nil)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body.nil? ? nil : body.to_json)
  end

  def jira_response_for(req)
    path = req.path.split("?", 2).first
    case
    when req.is_a?(Net::HTTP::Get) && path == "/rest/api/3/search/jql"
      http_response(200, { "issues" => [] })
    when req.is_a?(Net::HTTP::Post) && path.match?(%r{\A/rest/api/3/issue/[^/]+/worklog\z})
      worklog_status == 201 ? http_response(201, { "id" => "10001" }) : http_response(worklog_status, {})
    when req.is_a?(Net::HTTP::Get) && path.match?(%r{\A/rest/api/3/issue/[^/]+\z})
      http_response(200, { "fields" => { "timetracking" => { "originalEstimateSeconds" => 0 } } })
    when req.is_a?(Net::HTTP::Put) && path.match?(%r{\A/rest/api/3/issue/[^/]+\z})
      http_response(204)
    else
      raise "unexpected Jira request: #{req.method} #{req.path}"
    end
  end

  def spec1_worklog_post
    jira_requests.find { |req| req.is_a?(Net::HTTP::Post) && req.path.include?("SPEC-1/worklog") }
  end
end
