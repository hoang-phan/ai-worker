require "rails_helper"

RSpec.describe Workflow, type: :model do
  let_jira_project("workflow-spec", repo_full_name: "org/repo")
  let(:pr_url) { "https://github.com/org/repo/pull/7" }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "SPEC-1", branch_name: "spec-1", status: :pending)
  end

  describe "transition delegators" do
    it "delegates to Workflows::Transitions" do
      expect(workflow.start!).to be true
      expect(workflow.reload).to be_implementing
      workflow.update!(status: :errored)
      expect(workflow.resume_status).to eq(:implementing)
      expect(workflow.resume!).to be true
      expect(workflow).not_to be_can_rollback_to_review
      expect(workflow.rollback_to_review!).to be false
      expect(workflow).not_to be_can_run_stage
      expect(workflow.request_stage_run!).to be false
      expect(workflow).not_to be_can_advance
    end
  end

  describe "AI_RUN_RESET" do
    it "covers processing and every ai_* column" do
      expected = Workflow.column_names.grep(/\Aai_/) + %w[processing]
      expect(Workflow::AI_RUN_RESET.keys.map(&:to_s)).to match_array(expected)
    end
  end

  describe "#slack_review_thread_ts=" do
    it "normalizes a Slack permalink to a thread timestamp" do
      workflow.slack_review_thread_ts = "https://acme.slack.com/archives/C123ABC/p1760000000123456"

      expect(workflow.slack_review_thread_ts).to eq("1760000000.123456")
    end
  end

  describe "#finish_ai_run!" do
    it "clears the ai run columns and applies the extra attributes in one update" do
      workflow.update!(running_ai_run)

      workflow.finish_ai_run!(auto_run: false)

      expect(workflow.reload).to have_finished_ai_run.and have_attributes(auto_run: false)
    end
  end

  describe "extracted API delegators" do
    it "keeps setting-list callers on the model" do
      workflow.skills = " a, b "

      expect(workflow.skill_list).to eq(%w[a b])
    end
  end

  describe "#local_test_before_review? and #post_pr_status" do
    let(:ready_project) { build_jira_project(local_test_enabled: true, local_url: "http://localhost:3000") }
    let(:plain_project) { build_jira_project(local_test_enabled: false, local_url: "http://localhost:3000") }

    it "is true for a development workflow on a local-test-ready project" do
      wf = build_jira_workflow(ready_project)
      expect(wf).to be_local_test_before_review
      expect(wf.post_pr_status).to eq(:local_testing)
    end

    it "is false when the project has local testing disabled" do
      wf = build_jira_workflow(plain_project)
      expect(wf).not_to be_local_test_before_review
      expect(wf.post_pr_status).to eq(:reviewing)
    end

    it "is false for pr_review and runbook workflows even on a ready project" do
      %i[pr_review runbook].each do |kind|
        wf = build_jira_workflow(ready_project)
        wf.kind = kind
        expect(wf).not_to be_local_test_before_review
        expect(wf.post_pr_status).to eq(:reviewing)
      end
    end
  end
end
