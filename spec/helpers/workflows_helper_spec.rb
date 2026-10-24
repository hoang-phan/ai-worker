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

  describe "#stage_runnable?" do
    let(:project) { build_jira_project }
    let(:workflow) { build_runbook_workflow(project, status: :implementing) }
    let(:stage) { build_runbook_stage(workflow, name: "Build", position: 1) }
    let(:other_stage) { build_runbook_stage(workflow, name: "Ship", position: 2) }

    it "allows the current stage of an idle implementing runbook" do
      expect(helper.stage_runnable?(workflow, stage, stage)).to be(true)
    end

    it "rejects another stage or a workflow that is processing" do
      expect(helper.stage_runnable?(workflow, other_stage, stage)).to be(false)

      workflow.update!(processing: true)
      expect(helper.stage_runnable?(workflow, stage, stage)).to be(false)
    end
  end

  describe "#workflow_details_partial" do
    it "selects the PR review partial before considering the project kind" do
      workflow = instance_double(Workflow, pr_review?: true, runbook?: false)
      project = instance_double(Project, personal?: true)

      expect(helper.workflow_details_partial(workflow, project)).to eq("workflows/details/pr_review")
    end

    it "selects the runbook partial before considering the project kind" do
      workflow = instance_double(Workflow, pr_review?: false, runbook?: true)
      project = instance_double(Project, personal?: true)

      expect(helper.workflow_details_partial(workflow, project)).to eq("workflows/details/runbook")
    end

    it "selects the task partial for a personal development workflow" do
      workflow = instance_double(Workflow, pr_review?: false, runbook?: false)
      project = instance_double(Project, personal?: true)

      expect(helper.workflow_details_partial(workflow, project)).to eq("workflows/details/task")
    end

    it "selects the Jira partial for a Jira development workflow" do
      workflow = instance_double(Workflow, pr_review?: false, runbook?: false)
      project = instance_double(Project, personal?: false)

      expect(helper.workflow_details_partial(workflow, project)).to eq("workflows/details/jira")
    end
  end

  describe "#current_stage_badge" do
    let(:stage) { Object.new }

    it "labels a waiting current stage" do
      workflow = instance_double(Workflow, waiting?: true)

      expect(helper.current_stage_badge(workflow, stage, stage)).to eq("waiting for Next")
    end

    it "labels a non-waiting current stage and leaves other stages blank" do
      workflow = instance_double(Workflow, waiting?: false)

      expect(helper.current_stage_badge(workflow, stage, stage)).to eq("current")
      expect(helper.current_stage_badge(workflow, Object.new, stage)).to be_nil
    end
  end

  describe "#workflow_advance_label" do
    let_jira_project("workflows-helper-spec")
    let(:workflow) { build_runbook_workflow(project) }
    let!(:first) { build_runbook_stage(workflow, name: "Build", position: 1) }

    before { build_runbook_stage(workflow, name: "Ship", position: 2) }

    it "names the following stage" do
      workflow.update!(status: :waiting, current_stage_id: first.id)

      expect(helper.workflow_advance_label(workflow)).to eq("Next: Ship")
    end

    it "is Finish at the last stage" do
      workflow.update!(status: :waiting, current_stage_id: workflow.stages.last.id)

      expect(helper.workflow_advance_label(workflow)).to eq("Finish")
    end
  end

  describe "#runbook_copy_source_options" do
    let(:project) { build_jira_project }

    it "is empty without runbooks" do
      build_jira_workflow(project)
      expect(helper.runbook_copy_source_options(project)).to eq([])
    end

    it "lists only runbooks, newest first, as [label, id]" do
      older = build_runbook_workflow(project)
      build_jira_workflow(project)
      newer = build_runbook_workflow(project, status: :implementing)

      expect(helper.runbook_copy_source_options(project)).to eq([
        [ "##{newer.id} #{newer.label} (implementing)", newer.id ],
        [ "##{older.id} #{older.label} (pending)", older.id ]
      ])
    end

    it "ignores other projects' runbooks" do
      build_runbook_workflow(build_jira_project)
      expect(helper.runbook_copy_source_options(project)).to eq([])
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
        allow(workflow).to receive(:pr_review?).and_return(true)
        expect(helper.workflow_kind_badges(workflow)).to eq('<span class="badge badge-neutral">review</span>')
      end
    end
  end
end
