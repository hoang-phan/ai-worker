require "rails_helper"

RSpec.describe Stages::TaskFinish, type: :service do
  let(:local_directory) { Dir.mktmpdir("task-finish-spec") }
  let(:project) do
    Project.create!(name: "Task finish #{SecureRandom.hex(4)}", kind: :jira,
                    repo_full_name: "acme/widgets", local_directory: local_directory)
  end
  let(:workflow) do
    project.workflows.create!(jira_ticket: "TASK-1", branch_name: "task-finish", github_reviewer: "octocat", status: :implementing,
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
end
