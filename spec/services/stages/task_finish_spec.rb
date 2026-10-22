require "rails_helper"

RSpec.describe Stages::TaskFinish, type: :service do
  let(:local_directory) { Dir.mktmpdir("task-finish-spec") }
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "TASK-1", branch_name: "task-finish", status: :implementing,
                                 processing: true, ai_pid: 123, ai_log_path: "/tmp/x.log",
                                 ai_started_at: Time.current, ai_log_offset: 42)
  end
  let(:stage) { workflow.stages.create!(stage_type: :task, name: "task") }
  let(:git) { class_double(Git::BranchService, push_current!: :pushed) }

  def finish(output = "agent output")
    described_class.new(workflow: workflow, stage: stage, project: project, git: git).call(output)
  end

  def actions = stage.stage_runs.reorder(:id).pluck(:action)

  after do
    FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory)
  end

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

    it "creates pending workflows and logs follow_ups_created" do
      finish(block("Fix A"))

      expect(follow_up_workflows.map { |w| [ w.summary, w.task_description, w.status, w.skills ] })
        .to eq([ [ "Fix A", "Task for Fix A", "pending", "ruby" ] ])
      expect(follow_up_workflows.first.position).to be > workflow.position
      expect(actions).to eq(%w[task_completed follow_ups_created task_pushed])
      expect(stage.stage_runs.find_by(action: "follow_ups_created").output).to include("Created 1 follow-up workflow", "Fix A")
    end

    it "creates at most 2" do
      finish(block("Fix A", "Fix B", "Fix C"))
      expect(follow_up_workflows.map(&:summary)).to eq([ "Fix A", "Fix B" ])
    end

    it "skips summaries matching an existing non-done workflow, but not a done one" do
      build_task_workflow(project, summary: "fix a!", status: :pending)
      build_task_workflow(project, summary: "Fix B", status: :done)

      finish(block("Fix A", "Fix B"))
      expect(follow_up_workflows.pluck(:summary)).to eq([ "fix a!", "Fix B", "Fix B" ])
      expect(stage.stage_runs.find_by(action: "follow_ups_created").output).to include("Created 1")
    end

    it "does nothing without a block" do
      finish
      expect(follow_up_workflows).to be_empty
      expect(actions).not_to include("follow_ups_created")
    end

    it "never fails the task when creating follow-ups raises" do
      allow(project).to receive(:next_workflow_position).and_raise("boom")

      expect { finish(block("Fix A")) }.not_to raise_error
      expect(workflow.reload.status).to eq "done"
      expect(actions).to eq(%w[task_completed task_pushed])
    end
  end
end
