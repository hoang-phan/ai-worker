require "rails_helper"

RSpec.describe StageExecutor, type: :service do
  let_jira_project("stage-executor-spec")
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "EXEC-1", branch_name: "executor", status: :implementing, **running_ai_run)
  end
  let(:stage) { workflow.stages.create!(stage_type: :task) }
  let(:handler) { instance_double(Stages::CompletionHandler, call: nil) }
  let(:handler_class) { class_double(Stages::CompletionHandler, new: handler) }

  it "fails without polling or starting when the project uses the live checkout" do
    allow(project).to receive(:runs_from_live_checkout?).and_return(true)
    ai_run_poll = instance_double(Stages::AiRunPoll)
    expect(ai_run_poll).not_to receive(:call)
    start_handler_class = class_double(Stages::StartHandler)
    expect(start_handler_class).not_to receive(:new)

    described_class.new(workflow, stage, ai_run_poll: ai_run_poll, start_handler_class: start_handler_class).call

    expect(stage.stage_runs.find_by(action: "failed").error).to include("live ai-worker checkout")
  end

  it "hands a finished run's output to the completion handler" do
    ai_run_poll = instance_double(Stages::AiRunPoll, call: "all done")

    described_class.new(workflow, stage, ai_run_poll: ai_run_poll, completion_handler_class: handler_class).call

    expect(handler_class).to have_received(:new).with(hash_including(workflow: workflow, stage: stage, project: project))
    expect(handler).to have_received(:call).with("all done")
  end

  it "aborts a conflicted merge through the injected git when the run fails" do
    stage.stage_runs.create!(action: "conflict_resolution_started")
    git = class_double(Git::BranchService, abort_merge!: nil)
    ai_run_poll = instance_double(Stages::AiRunPoll)
    allow(ai_run_poll).to receive(:call).and_raise(AiCli::CommandError, "boom")

    described_class.new(workflow, stage, git: git, ai_run_poll: ai_run_poll).call

    expect(git).to have_received(:abort_merge!).with(project)
    expect(stage.stage_runs.find_by(action: "failed").error).to eq("boom")
  end

  it "does not complete while the run is still going" do
    ai_run_poll = instance_double(Stages::AiRunPoll, call: nil)
    handler_class = class_double(Stages::CompletionHandler, new: nil)

    described_class.new(workflow, stage, ai_run_poll: ai_run_poll, completion_handler_class: handler_class).call

    expect(handler_class).not_to have_received(:new)
  end

  it "fails the stage when the handler raises a command error" do
    ai_run_poll = instance_double(Stages::AiRunPoll, call: "x")
    allow(handler).to receive(:call).and_raise(AiCli::CommandError, "boom")

    described_class.new(workflow, stage, ai_run_poll: ai_run_poll, completion_handler_class: handler_class).call

    expect(stage.stage_runs.find_by(action: "failed").error).to eq "boom"
  end

  describe "injected collaborators" do
    let(:stage) { build_stage(workflow, :ci_check) }

    it "uses injected collaborators for a finished ci_check stage" do
      ai_run_poll = instance_double(Stages::AiRunPoll, call: "green")
      github = double("Github::Client")
      git = double("Git::BranchService")
      handoff = double("Stages::ReviewHandoff")

      described_class.new(
        workflow, stage, github: github, git: git, ai_run_poll: ai_run_poll, handoff: handoff,
        completion_handler_class: handler_class
      ).call

      expect(handler_class).to have_received(:new).with(hash_including(github: github, git: git, handoff: handoff))
      expect(handler).to have_received(:call).with("green")
    end

    it "uses the injected GitHub client in the default handoff" do
      implementation = build_stage(workflow, :implementation)
      pr_url = "https://github.com/acme/widgets/pull/99"
      ai_run_poll = instance_double(Stages::AiRunPoll, call: "opened #{pr_url}")
      github = instance_double(Github::Client, find_pr_url: pr_url, enable_auto_merge!: nil)

      described_class.new(workflow, implementation, github: github, ai_run_poll: ai_run_poll).call

      expect(workflow.reload).to have_attributes(status: "reviewing", github_pr_url: pr_url).and have_finished_ai_run
      expect(stage_actions(implementation)).to eq %w[ran_implementation auto_merge_enabled]
      expect(github).to have_received(:find_pr_url).with(branch_name: "executor", jira_ticket: "EXEC-1", output: "opened #{pr_url}")
      expect(github).to have_received(:enable_auto_merge!).with(pr_url)
    end
  end

  describe "starting a stage" do
    let(:workflow) { build_jira_workflow(project, jira_ticket: "EXEC-2", branch_name: "executor", status: :implementing) }
    let(:git) { class_double(Git::BranchService, create_branch!: nil) }
    let(:runner) { class_double(AiCli::Runner, start: 777) }
    let(:tooling) { Stages::RunTooling::Tooling.new(runner: runner, poller_class: AiCli::RunPoller) }

    it "builds a launcher and injects it into the start handler" do
      stage = build_stage(workflow, :implementation)
      launcher = instance_double(Stages::AiRunLauncher)
      start_handler = instance_double(Stages::StartHandler, call: nil)
      handoff = instance_double(Stages::ReviewHandoff)
      launcher_class = class_double(Stages::AiRunLauncher, new: launcher)
      start_handler_class = class_double(Stages::StartHandler, new: start_handler)

      described_class.new(workflow, stage, handoff: handoff, launcher_class: launcher_class, start_handler_class: start_handler_class).call

      expect(launcher_class).to have_received(:new).with(workflow: workflow, stage: stage, project: project, runner: AiCli::Runner)
      expect(start_handler_class).to have_received(:new).with(
        hash_including(workflow: workflow, stage: stage, project: project, handoff: handoff, launcher: launcher)
      )
      expect(start_handler).to have_received(:call)
    end

    it "passes its launcher to conflict resolution finishing" do
      stage = build_stage(workflow, :pr_check)
      workflow.update!(running_ai_run)
      launcher = instance_double(Stages::AiRunLauncher)
      finish = instance_double(Stages::ConflictResolutionFinish, call: nil)
      ai_run_poll = instance_double(Stages::AiRunPoll, call: "merged")
      allow(stage).to receive(:resolving_conflicts?).and_return(true)
      launcher_class = class_double(Stages::AiRunLauncher, new: launcher)
      finish_class = class_double(Stages::ConflictResolutionFinish, new: finish)

      described_class.new(
        workflow, stage, ai_run_poll: ai_run_poll, launcher_class: launcher_class, conflict_resolution_finish_class: finish_class
      ).call

      expect(finish_class).to have_received(:new).with(
        hash_including(workflow: workflow, stage: stage, project: project, launcher: launcher)
      )
      expect(finish).to have_received(:call).with("merged")
    end

    it "fails the stage when the start path raises a command error" do
      stage = build_stage(workflow, :implementation, prompt: "implement it")
      allow(git).to receive(:create_branch!).and_raise(Git::CommandError, "no branch")

      described_class.new(workflow, stage, git: git, tooling: tooling).call

      expect(stage.stage_runs.find_by(action: "failed").error).to eq "no branch"
    end

    it "starts an implementation stage and records the detached run" do
      stage = build_stage(workflow, :implementation, prompt: "implement it")

      described_class.new(workflow, stage, git: git, tooling: tooling).call

      expect(workflow.reload).to have_attributes(processing: true, ai_pid: 777)
      expect(stage_actions(stage)).to eq %w[started]
      expect(git).to have_received(:create_branch!).with(project, "executor")
      expect(runner).to have_received(:start).with(
        project.local_directory,
        kind_of(String),
        hash_including(log_path: kind_of(String), provider: nil)
      )
    end
  end
end
