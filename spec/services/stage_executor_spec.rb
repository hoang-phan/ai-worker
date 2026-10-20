require "rails_helper"

RSpec.describe StageExecutor, type: :service do
  let(:local_directory) { Dir.mktmpdir("stage-executor-spec") }
  let(:project) do
    Project.create!(name: "Executor #{SecureRandom.hex(4)}", kind: :jira, repo_full_name: "acme/widgets",
                    local_directory: local_directory)
  end
  let(:workflow) do
    project.workflows.create!(jira_ticket: "EXEC-1", branch_name: "executor", github_reviewer: "octocat", status: :implementing, processing: true,
                              ai_pid: 123, ai_log_path: "/tmp/x.log", ai_started_at: Time.current, ai_log_offset: 0)
  end
  let(:stage) { workflow.stages.create!(stage_type: :task) }
  let(:handler) { instance_double(Stages::CompletionHandler, call: nil) }

  after do
    FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory)
  end

  it "hands a finished run's output to the completion handler" do
    poller = instance_double(AiCli::RunPoller, call: [ :finished, "all done" ], log_offset: 0)
    allow(AiCli::RunPoller).to receive(:new).and_return(poller)
    allow(Stages::CompletionHandler).to receive(:new).and_return(handler)

    described_class.new(workflow, stage).call

    expect(Stages::CompletionHandler).to have_received(:new).with(hash_including(workflow: workflow, stage: stage, project: project))
    expect(handler).to have_received(:call).with("all done")
  end

  it "does not complete while the run is still going" do
    poller = instance_double(AiCli::RunPoller, call: [ :running, nil ], log_offset: 0)
    allow(AiCli::RunPoller).to receive(:new).and_return(poller)
    allow(Stages::CompletionHandler).to receive(:new)

    described_class.new(workflow, stage).call

    expect(Stages::CompletionHandler).not_to have_received(:new)
  end

  it "fails the stage when the handler raises a command error" do
    poller = instance_double(AiCli::RunPoller, call: [ :finished, "x" ], log_offset: 0)
    allow(AiCli::RunPoller).to receive(:new).and_return(poller)
    allow(Stages::CompletionHandler).to receive(:new).and_return(handler)
    allow(handler).to receive(:call).and_raise(AiCli::CommandError, "boom")

    described_class.new(workflow, stage).call

    expect(stage.stage_runs.find_by(action: "failed").error).to eq "boom"
  end
end
