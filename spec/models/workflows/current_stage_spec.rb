require "rails_helper"

RSpec.describe Workflows::CurrentStage do
  let_tmpdir(:local_directory, "current-stage-spec")
  let(:project_attrs) { { repo_full_name: "org/repo", local_directory: local_directory } }
  let(:project) { build_jira_project(**project_attrs) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "CS-1", branch_name: "cs-1", status: :implementing)
  end

  def call(wf = workflow) = described_class.new(wf).call

  describe "runbooks" do
    let(:runbook) { build_runbook_workflow(project, status: :waiting) }
    let!(:first) { build_runbook_stage(runbook, name: "One", position: 1) }
    let!(:second) { build_runbook_stage(runbook, name: "Two", position: 2) }

    it "returns the stage at current_stage_id" do
      runbook.update!(current_stage_id: second.id)
      expect(call(runbook)).to eq(second)
    end

    it "returns nil when current_stage_id is unset" do
      expect(call(runbook)).to be_nil
    end
  end

  it "returns the seeded implementation stage of a jira development workflow" do
    expect(call).to eq(workflow.stages.find_by!(stage_type: :implementation))
  end

  it "maps implementing to a lazily created simple_implementation stage on a ci_loop project" do
    project.update!(flow: :ci_loop, ci_command: "bin/ci")
    workflow.stages.where(stage_type: :simple_implementation).destroy_all

    stage = nil
    expect { stage = call }.to change { workflow.stages.simple_implementation.count }.from(0).to(1)
    expect(stage).to be_simple_implementation
  end

  it "resolves implementing to the seeded simple_implementation stage and reviewing to pr_check on the ci_loop flow" do
    ci_workflow = build_ci_workflow(build_ci_project)

    expect(call(ci_workflow)).to eq(ci_workflow.stages.find_by!(stage_type: :simple_implementation))
    ci_workflow.update!(status: :reviewing)
    expect(call(ci_workflow)).to eq(ci_workflow.stages.find_by!(stage_type: :pr_check))
  end

  it "creates a lazy stage type once and reuses it" do
    workflow.update!(status: :merged)

    first = nil
    expect { first = call }.to change { workflow.stages.jira_update.count }.from(0).to(1)
    expect(first).to be_jira_update
    expect { expect(call).to eq(first) }.not_to change { Stage.count }
  end

  it "maps implementing to the task stage on a personal project" do
    personal = build_personal_project(local_directory: local_directory)
    task = build_task_workflow(personal, status: :implementing)
    expect(call(task)).to eq(task.stages.find_by!(stage_type: :task))
  end

  it "maps a pr_review workflow to its pr_review stage" do
    review = build_pr_review_workflow(project, status: :implementing)
    expect(call(review)).to eq(review.stages.find_by!(stage_type: :pr_review))
  end

  it "returns nil for a terminal status" do
    workflow.update!(status: :done)
    expect(call).to be_nil
  end
end
