require "rails_helper"

RSpec.describe StageExecutor, type: :service do
  let_tmpdir(:local_directory, "stage-executor-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "EXEC-1", branch_name: "executor", status: :implementing, **running_ai_run)
  end
  let(:stage) { workflow.stages.create!(stage_type: :task) }
  let(:handler) { instance_double(Stages::CompletionHandler, call: nil) }

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

  describe "injected collaborators" do
    let(:stage) { workflow.stages.create!(stage_type: :ci_check, name: "ci_check") }

    it "polls a ci_check stage through the injected tooling and builds the github client once" do
      poller_class = class_double(Ci::CheckPoller)
      poller = instance_double(Ci::CheckPoller, call: [ :finished, "green" ], log_offset: 5)
      tooling = Stages::RunTooling::Tooling.new(runner: double("runner"), poller_class: poller_class)
      github = double("Github::Client")
      git = double("Git::BranchService")
      allow(poller_class).to receive(:new).and_return(poller)
      allow(Stages::CompletionHandler).to receive(:new).and_return(handler)

      described_class.new(workflow, stage, github: github, git: git, tooling: tooling).call

      expect(poller_class).to have_received(:new).with(hash_including(pid: 123, stale_after: StageExecutor::STALE_AFTER))
      expect(Stages::CompletionHandler).to have_received(:new).with(hash_including(github: github, git: git))
      expect(handler).to have_received(:call).with("green")
      expect(workflow.reload.ai_log_offset).to eq 5
    end

    it "picks the plain command tooling for a ci_check stage by default" do
      poller = instance_double(Ci::CheckPoller, call: [ :running, nil ], log_offset: 0)
      allow(Ci::CheckPoller).to receive(:new).and_return(poller)

      described_class.new(workflow, stage).call

      expect(Ci::CheckPoller).to have_received(:new)
    end
  end

  describe "starting a stage" do
    let(:workflow) { build_jira_workflow(project, jira_ticket: "EXEC-2", branch_name: "executor", status: :implementing) }
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

    it "builds a launcher and injects it into the start handler" do
      stage = workflow.stages.create!(stage_type: :implementation, name: "implementation")
      launcher = instance_double(Stages::AiRunLauncher)
      start_handler = instance_double(Stages::StartHandler, call: nil)
      allow(Stages::AiRunLauncher).to receive(:new).and_return(launcher)
      allow(Stages::StartHandler).to receive(:new).and_return(start_handler)

      described_class.new(workflow, stage).call

      expect(Stages::AiRunLauncher).to have_received(:new).with(workflow: workflow, stage: stage, project: project, runner: AiCli::Runner)
      expect(Stages::StartHandler).to have_received(:new).with(hash_including(workflow: workflow, stage: stage, project: project, launcher: launcher))
      expect(start_handler).to have_received(:call)
    end

    it "passes its launcher to conflict resolution finishing" do
      stage = workflow.stages.create!(stage_type: :pr_check, name: "pr_check")
      workflow.update!(running_ai_run)
      launcher = instance_double(Stages::AiRunLauncher)
      finish = instance_double(Stages::ConflictResolutionFinish, call: nil)
      allow(stage).to receive(:resolving_conflicts?).and_return(true)
      allow(AiCli::RunPoller).to receive(:new).and_return(instance_double(AiCli::RunPoller, call: [ :finished, "merged" ], log_offset: 0))
      allow(Stages::AiRunLauncher).to receive(:new).and_return(launcher)
      allow(Stages::ConflictResolutionFinish).to receive(:new).and_return(finish)

      described_class.new(workflow, stage).call

      expect(Stages::ConflictResolutionFinish).to have_received(:new).with(
        hash_including(workflow: workflow, stage: stage, project: project, start_ai_run: launcher)
      )
      expect(finish).to have_received(:call).with("merged")
    end

    %w[implementation task pr_review jira_update uat_test local_test runbook_step pr_check].each do |type|
      it "starts a #{type} stage through the start handler" do
        stage = workflow.stages.create!(stage_type: type, name: type)
        described_class.new(workflow, stage).call

        expect(workflow.reload).to have_attributes(processing: true, ai_pid: 777)
        expect(stage_actions(stage)).to eq %w[started]
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
      workflow.update!(running_ai_run)
      allow(stage).to receive(:resolving_conflicts?).and_return(true)
      allow(Git::BranchService).to receive(:merge_in_progress?).and_return(false)
      allow(AiCli::RunPoller).to receive(:new).and_return(instance_double(AiCli::RunPoller, call: [ :finished, "merged" ], log_offset: 0))
      described_class.new(workflow, stage).call

      expect(stage_actions(stage)).to eq %w[conflicts_resolved started]
      expect(workflow.reload).to have_attributes(processing: true, ai_pid: 777)
    end
  end
end
