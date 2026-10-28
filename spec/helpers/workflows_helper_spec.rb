require "rails_helper"

RSpec.describe WorkflowsHelper, type: :helper do
  expected = {
    "pending" => "badge-neutral",
    "implementing" => "badge-info",
    "reviewing" => "badge-info",
    "done" => "badge-success",
    "errored" => "badge-danger",
    "merged" => "badge-success",
    "jira_updated" => "badge-success",
    "waiting" => "badge-info",
    "uat_waiting" => "badge-info",
    "uat_tested" => "badge-success",
    "uat_testing" => "badge-info",
    "local_testing" => "badge-info",
    "ci_checking" => "badge-info",
    "ci_verifying" => "badge-info",
    "opening_pr" => "badge-info"
  }

  describe "#workflow_status_badge_class" do
    it "has an explicit expectation for every Workflow status" do
      expect(expected.keys).to match_array(Workflow.statuses.keys)
    end

    expected.each do |status, css|
      it "maps #{status} to #{css}" do
        expect(helper.workflow_status_badge_class(status)).to eq(css)
        expect(helper.workflow_status_badge_class(Workflow.new(status: status))).to eq(css)
      end
    end

    it "falls back to badge-neutral for unknown statuses" do
      expect(helper.workflow_status_badge_class("brand_new")).to eq("badge-neutral")
    end
  end

  describe "#workflow_status_badge" do
    it "renders a span with the badge class and status text" do
      html = helper.workflow_status_badge(Workflow.new(status: "errored"))
      expect(html).to eq('<span class="badge badge-danger">errored</span>')
    end
  end

  describe "workflow row helpers" do
    let(:project) { build_jira_project }
    let(:workflow) { build_jira_workflow(project) }

    describe "#workflow_kind_badges" do
      it "is empty for a development workflow" do
        expect(helper.workflow_kind_badges(workflow)).to be_blank
      end

      it "badges runbooks" do
        runbook = build_runbook_workflow(project)
        expect(helper.workflow_kind_badges(runbook)).to eq('<span class="badge badge-neutral">runbook</span>')
      end

      it "badges PR reviews" do
        review = build_pr_review_workflow(project)
        expect(helper.workflow_kind_badges(review)).to eq('<span class="badge badge-neutral">review</span>')
      end
    end
  end
end
