require "rails_helper"

RSpec.describe Stages::TaskFinish, type: :service do
  let_tmpdir(:local_directory, "task-finish-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "TASK-1", branch_name: "task-finish", status: :implementing, **running_ai_run)
  end
  let(:stage) { workflow.stages.create!(stage_type: :task, name: "task") }
  let(:git) { class_double(Git::BranchService, push_current!: :pushed) }

  def finish(output = "agent output")
    described_class.new(workflow: workflow, stage: stage, project: project, git: git).call(output)
  end

  def actions = stage.stage_runs.reorder(:id).pluck(:action)

  it "resets AI-run state, marks the workflow done and logs task_completed and task_pushed" do
    finish

    expect(workflow.reload).to have_attributes(status: "done", processing: false, ai_pid: nil, ai_log_path: nil,
                                                ai_started_at: nil, ai_log_offset: 0)
    expect(actions).to eq(%w[task_completed task_pushed])
    expect(stage.stage_runs.find_by(action: "task_completed").output).to eq "agent output"
    expect(git).to have_received(:push_current!).with(project)
  end

  it "does not log a push when nothing was pushed" do
    allow(git).to receive(:push_current!).and_return(:nothing)

    finish
    expect(actions).to eq(%w[task_completed])
  end

  it "logs a failed push without failing" do
    allow(git).to receive(:push_current!).and_raise(Git::CommandError, "rejected")

    expect { finish }.not_to raise_error
    expect(workflow.reload.status).to eq "done"
    expect(actions).to eq(%w[task_completed task_push_failed])
    expect(stage.stage_runs.find_by(action: "task_push_failed").error).to eq "rejected"
  end

  describe "follow-ups" do
    let(:project) { build_personal_project(local_directory: local_directory, default_skills: "ruby") }
    let(:workflow) { build_task_workflow(project, status: :implementing, processing: true) }

    def block(*summaries)
      rows = summaries.map { |summary| { summary: summary, task: "Task for #{summary}" } }
      "work done\nFOLLOW_UPS_BEGIN\n#{rows.to_json}\nFOLLOW_UPS_END\n"
    end

    def follow_up_workflows = project.workflows.where.not(id: workflow.id).order(:id)

    it "imports the proposals and logs follow_ups_created" do
      finish(block("Fix A"))

      expect(follow_up_workflows.pluck(:summary)).to eq([ "Fix A" ])
      expect(actions).to eq(%w[task_completed follow_ups_created task_pushed])
      expect(stage.stage_runs.find_by(action: "follow_ups_created").output).to include("Created 1 follow-up workflow", "Fix A")
    end

    it "does nothing without a block" do
      finish
      expect(follow_up_workflows).to be_empty
      expect(actions).not_to include("follow_ups_created")
    end

    it "does not log when the importer creates nothing" do
      build_task_workflow(project, summary: "Fix A", status: :pending)

      finish(block("Fix A"))
      expect(actions).to eq(%w[task_completed task_pushed])
    end

    it "skips follow-ups for a non-personal project" do
      jira_project = build_jira_project(local_directory: local_directory)
      jira_workflow = build_jira_workflow(jira_project, jira_ticket: "TASK-2", branch_name: "t2", status: :implementing)
      jira_stage = jira_workflow.stages.create!(stage_type: :task, name: "task")

      described_class.new(workflow: jira_workflow, stage: jira_stage, project: jira_project, git: git).call(block("Fix A"))
      expect(jira_project.workflows.count).to eq 1
    end

    it "never fails the task when creating follow-ups raises" do
      allow(project).to receive(:next_workflow_position).and_raise("boom")

      expect { finish(block("Fix A")) }.not_to raise_error
      expect(workflow.reload.status).to eq "done"
      expect(actions).to eq(%w[task_completed task_pushed])
    end
  end
end
