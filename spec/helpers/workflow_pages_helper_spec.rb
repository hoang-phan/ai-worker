require "rails_helper"

RSpec.describe WorkflowPagesHelper, type: :helper do
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

  describe "#workflow_advance_label" do
    let_jira_project("workflow-pages-helper-spec")
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
end
