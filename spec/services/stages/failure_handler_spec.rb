require "rails_helper"

RSpec.describe Stages::FailureHandler, type: :service do
  let(:local_directory) { Dir.mktmpdir("failure-handler-spec") }
  let(:project) do
    Project.create!(name: "Failure handler #{SecureRandom.hex(4)}", kind: :jira,
                    repo_full_name: "acme/widgets", local_directory: local_directory)
  end
  let(:workflow) do
    project.workflows.create!(jira_ticket: "FAIL-1", branch_name: "failure-handler", github_reviewer: "octocat", status: :implementing,
                              processing: true, ai_pid: 123, ai_log_path: "/tmp/x.log",
                              ai_started_at: Time.current, ai_log_offset: 42, auto_run: true)
  end
  let(:stage) { workflow.stages.create!(stage_type: :implementation) }
  let(:error) { AiCli::CommandError.new("boom") }
  let(:threshold) { 3 }

  def handle
    described_class.new(workflow: workflow, stage: stage, project: project, error: error, threshold: threshold).call
  end

  before { allow(Git::BranchService).to receive(:abort_merge!) }

  after do
    FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory)
  end

  it "clears the AI-run fields, stops auto-run and logs the failure" do
    handle

    workflow.reload
    expect(workflow).to have_attributes(processing: false, ai_pid: nil, ai_log_path: nil, ai_started_at: nil,
                                        ai_log_offset: 0, auto_run: false, status: "implementing")
    expect(stage.stage_runs.where(action: "failed").sole).to have_attributes(error: "boom")
    expect(Git::BranchService).not_to have_received(:abort_merge!)
  end

  it "aborts an in-progress merge when the stage was resolving conflicts" do
    stage.stage_runs.create!(action: "conflict_resolution_started")

    handle

    expect(Git::BranchService).to have_received(:abort_merge!).with(project)
    expect(stage.stage_runs.pluck(:action)).to include("failed")
  end

  it "keeps the workflow retryable below the threshold" do
    1.times { stage.stage_runs.create!(action: "failed") }

    handle

    expect(workflow.reload.status).to eq("implementing")
  end

  it "parks the workflow as errored at the threshold" do
    2.times { stage.stage_runs.create!(action: "failed") }
    stage.stage_runs.create!(action: "started")

    expect { handle }.to change { workflow.reload.status }.from("implementing").to("errored")
    expect(workflow.processing).to be(false)
  end
end
