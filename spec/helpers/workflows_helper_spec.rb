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
    let(:stage) { Object.new }
    let(:workflow) { instance_double(Workflow, runbook?: true, implementing?: true, processing?: false) }

    it "allows the current stage of an idle implementing runbook" do
      expect(helper.stage_runnable?(workflow, stage, stage)).to be(true)
    end

    it "rejects another stage or a workflow that is processing" do
      expect(helper.stage_runnable?(workflow, Object.new, stage)).to be(false)

      allow(workflow).to receive(:processing?).and_return(true)
      expect(helper.stage_runnable?(workflow, stage, stage)).to be(false)
    end
  end

  describe "#logged_hours" do
    it "formats seconds as hours without insignificant zeros" do
      expect(helper.logged_hours(5400)).to eq("1.5")
      expect(helper.logged_hours(3600)).to eq("1")
      expect(helper.logged_hours(0)).to eq("0")
      expect(helper.logged_hours(1234)).to eq("0.34")
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

  describe "#runbook_copy_source_options" do
    let(:project) { build_jira_project }

    it "is empty without runbooks" do
      build_jira_workflow(project)
      expect(helper.runbook_copy_source_options(project)).to eq([])
    end

    it "lists only runbooks, newest first, as [label, id]" do
      older = project.workflows.create!(kind: :runbook)
      build_jira_workflow(project)
      newer = project.workflows.create!(kind: :runbook, status: :implementing)

      expect(helper.runbook_copy_source_options(project)).to eq([
        [ "##{newer.id} #{newer.label} (implementing)", newer.id ],
        [ "##{older.id} #{older.label} (pending)", older.id ]
      ])
    end

    it "ignores other projects' runbooks" do
      build_jira_project.workflows.create!(kind: :runbook)
      expect(helper.runbook_copy_source_options(project)).to eq([])
    end
  end

  describe "workflow row helpers" do
    let(:project) { build_jira_project }
    let(:workflow) { build_jira_workflow(project) }

    describe "#jira_synced_phrase" do
      it "is nil when never synced" do
        expect(helper.jira_synced_phrase(workflow)).to be_nil
      end

      it "says how long ago hours were synced" do
        workflow.jira_logged_synced_at = 5.minutes.ago
        expect(helper.jira_synced_phrase(workflow)).to eq("synced 5 minutes ago")
      end
    end

    describe "#workflow_kind_badges" do
      it "is empty for a development workflow" do
        expect(helper.workflow_kind_badges(workflow)).to be_blank
      end

      it "badges runbooks" do
        runbook = project.workflows.create!(kind: :runbook)
        expect(helper.workflow_kind_badges(runbook)).to eq('<span class="badge badge-neutral">runbook</span>')
      end

      it "badges PR reviews" do
        allow(workflow).to receive(:pr_review?).and_return(true)
        expect(helper.workflow_kind_badges(workflow)).to eq('<span class="badge badge-neutral">review</span>')
      end
    end

    describe "#workflow_logged_time_badge" do
      it "is nil for non-development workflows" do
        runbook = project.workflows.create!(kind: :runbook)
        expect(helper.workflow_logged_time_badge(runbook, 3600)).to be_nil
      end

      it "shows Not logged without seconds" do
        expect(helper.workflow_logged_time_badge(workflow, nil)).to eq('<span class="badge badge-neutral">Not logged</span>')
      end

      it "shows hours with a plain title when never synced" do
        expect(helper.workflow_logged_time_badge(workflow, 5400)).to eq('<span class="badge badge-success" title="Hours you have logged in Jira">1.5 h</span>')
      end

      it "adds the synced phrase to the title" do
        workflow.jira_logged_synced_at = 2.hours.ago
        expect(helper.workflow_logged_time_badge(workflow, 3600)).to include('title="Hours you have logged in Jira, synced about 2 hours ago"')
      end
    end

    describe "#time_log_checkbox_data" do
      it "marks unlogged rows as select-all targets" do
        expect(helper.time_log_checkbox_data(0)).to eq(select_all_target: "row")
        expect(helper.time_log_checkbox_data(nil)).to eq(select_all_target: "row")
      end

      it "leaves logged rows out" do
        expect(helper.time_log_checkbox_data(3600)).to eq({})
      end
    end
  end
end
