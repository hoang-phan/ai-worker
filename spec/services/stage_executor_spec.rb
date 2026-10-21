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

  describe "starting a stage" do
    let(:workflow) { project.workflows.create!(jira_ticket: "EXEC-2", branch_name: "executor", github_reviewer: "octocat", status: :implementing) }
    let(:github) { double("Github::Client", merged?: false, review_decision: "CHANGES_REQUESTED", pr_info: { "state" => "OPEN", "head_ref" => "feature" }, checkout_pr!: nil) }
    let(:browser_run) { instance_double(AiCli::BrowserTestRun, mcp_config_path: "/tmp/mcp.json", env: {}, disallowed_tools: []) }

    before do
      allow(Github::Client).to receive(:new).and_return(github)
      allow(Git::BranchService).to receive_messages(create_branch!: nil, checkout_remote_branch!: nil, update_with_main!: :updated)
      allow(AiCli::BrowserTestRun).to receive(:new).and_return(double(validate!: browser_run))
      allow(AiCli::Runner).to receive(:start).and_return(777)
      allow(Prompts::StagePrompt).to receive(:new).and_return(instance_double(Prompts::StagePrompt, body: "p", slack_message: "m"))
      allow(Stages::WorkflowRunGate).to receive(:new).and_return(instance_double(Stages::WorkflowRunGate, call: Stages::WorkflowRunGate::Result.new(passed: true)))
      allow(Stages::PrCheckDecision).to receive(:new).and_return(double(call: Struct.new(:decision, :actions).new(:changes_requested, [])))
      allow_any_instance_of(Stages::ReviewHandoff).to receive(:reviewers).and_return([ "octocat" ]) # rubocop:disable RSpec/AnyInstance
    end

    %w[implementation task pr_review jira_update uat_test local_test runbook_step pr_check].each do |type|
      it "starts a #{type} stage through the start handler" do
        stage = workflow.stages.create!(stage_type: type, name: type)
        described_class.new(workflow, stage).call

        expect(workflow.reload).to have_attributes(processing: true, ai_pid: 777)
        expect(stage.stage_runs.reorder(:id).pluck(:action)).to eq %w[started]
      end
    end

    it "fails the stage when the start handler raises a command error" do
      stage = workflow.stages.create!(stage_type: :implementation, name: "implementation")
      allow(Git::BranchService).to receive(:create_branch!).and_raise(Git::CommandError, "no branch")
      described_class.new(workflow, stage).call

      expect(stage.stage_runs.find_by(action: "failed").error).to eq "no branch"
    end

    it "starts the review-fix run after conflict resolution via the start handler" do
      stage = workflow.stages.create!(stage_type: :pr_check, name: "pr_check")
      workflow.update!(processing: true, ai_pid: 1, ai_log_path: "/tmp/x.log", ai_started_at: Time.current, ai_log_offset: 0)
      allow(stage).to receive(:resolving_conflicts?).and_return(true)
      allow(Git::BranchService).to receive(:merge_in_progress?).and_return(false)
      allow(AiCli::RunPoller).to receive(:new).and_return(instance_double(AiCli::RunPoller, call: [ :finished, "merged" ], log_offset: 0))
      described_class.new(workflow, stage).call

      expect(stage.stage_runs.reorder(:id).pluck(:action)).to eq %w[conflicts_resolved started]
      expect(workflow.reload).to have_attributes(processing: true, ai_pid: 777)
    end
  end
end
