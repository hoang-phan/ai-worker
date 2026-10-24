require "rails_helper"

RSpec.describe Stages::StartHandler, type: :service do
  let_tmpdir(:local_directory, "start-handler-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "START-1", branch_name: "start-handler", github_pr_url: "https://github.com/acme/widgets/pull/1", status: :implementing)
  end
  let(:stage_type) { :implementation }
  let(:stage) { workflow.stages.create!(stage_type: stage_type, name: stage_type.to_s) }
  let(:github) { double("Github::Client") }
  let(:git) { class_double(Git::BranchService, create_branch!: nil, checkout_remote_branch!: nil, update_with_main!: :updated) }
  let(:prompt) { instance_double(Prompts::StagePrompt, body: "the prompt") }
  let(:handoff) { double("Stages::ReviewHandoff", reviewers: [ "octocat" ]) }
  let(:launcher) { spy("Stages::AiRunLauncher") }
  let(:browser_run) do
    instance_double(AiCli::BrowserTestRun, mcp_config_path: "/tmp/mcp.json", env: { "TEST_USER" => "u" }, disallowed_tools: [ "Bash" ])
  end

  def handler
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, git: git, prompt: prompt, handoff: handoff, launcher: launcher)
  end

  def expect_run_started(prompt_text = "the prompt", **options)
    expect(launcher).to have_received(:call).with(prompt_text, **options)
  end

  describe "implementation" do
    it "creates the branch and starts the agent" do
      handler.call

      expect(git).to have_received(:create_branch!).with(project, "start-handler")
      expect_run_started
    end

    it "propagates a branch error without starting the agent" do
      allow(git).to receive(:create_branch!).and_raise(Git::CommandError, "nope")

      expect { handler.call }.to raise_error(Git::CommandError, "nope")
      expect(launcher).not_to have_received(:call)
    end
  end

  describe "task" do
    let(:stage_type) { :task }

    it "starts the agent directly" do
      handler.call

      expect(git).not_to have_received(:create_branch!)
      expect_run_started
    end
  end

  describe "jira_update" do
    let(:stage_type) { :jira_update }

    it "starts the agent" do
      handler.call
      expect_run_started
    end
  end

  describe "pr_review" do
    let(:stage_type) { :pr_review }

    it "delegates to Stages::PrReviewStart" do
      starter = instance_double(Stages::PrReviewStart, call: nil)
      allow(Stages::PrReviewStart).to receive(:new).and_return(starter)
      handler.call

      expect(Stages::PrReviewStart).to have_received(:new)
        .with(workflow: workflow, stage: stage, project: project, github: github, git: git, prompt: prompt, launcher: launcher)
      expect(starter).to have_received(:call)
    end
  end

  describe "uat_test" do
    let(:stage_type) { :uat_test }

    it "validates the browser run and starts the agent with its MCP config, env and disallowed tools" do
      allow(AiCli::BrowserTestRun).to receive(:new).with(project, workflow, kind: :uat).and_return(double(validate!: browser_run))
      handler.call

      expect_run_started(mcp_config: "/tmp/mcp.json", env: { "TEST_USER" => "u" }, disallowed_tools: [ "Bash" ])
    end

    it "delegates to BrowserTestStart for the uat kind" do
      starter = instance_double(Stages::BrowserTestStart, call: nil)
      allow(Stages::BrowserTestStart).to receive(:new).and_return(starter)
      handler.call

      expect(Stages::BrowserTestStart).to have_received(:new)
        .with(workflow: workflow, project: project, kind: :uat, prompt: prompt, git: git, launcher: launcher)
      expect(starter).to have_received(:call)
    end

    it "propagates a validation error" do
      invalid = double("AiCli::BrowserTestRun")
      allow(invalid).to receive(:validate!).and_raise(ArgumentError, "no uat")
      allow(AiCli::BrowserTestRun).to receive(:new).and_return(invalid)

      expect { handler.call }.to raise_error(ArgumentError, "no uat")
      expect(launcher).not_to have_received(:call)
    end
  end

  describe "local_test" do
    let(:stage_type) { :local_test }

    it "checks out the PR branch and starts the browser run" do
      allow(AiCli::BrowserTestRun).to receive(:new).with(project, workflow, kind: :local).and_return(double(validate!: browser_run))
      handler.call

      expect(git).to have_received(:checkout_remote_branch!).with(project, "start-handler")
      expect_run_started(mcp_config: "/tmp/mcp.json", env: { "TEST_USER" => "u" }, disallowed_tools: [ "Bash" ])
    end
  end

  describe "local_test delegation" do
    let(:stage_type) { :local_test }

    it "delegates to BrowserTestStart for the local kind" do
      starter = instance_double(Stages::BrowserTestStart, call: nil)
      allow(Stages::BrowserTestStart).to receive(:new).and_return(starter)
      handler.call

      expect(Stages::BrowserTestStart).to have_received(:new)
        .with(workflow: workflow, project: project, kind: :local, prompt: prompt, git: git, launcher: launcher)
      expect(starter).to have_received(:call)
    end
  end

  describe "runbook_step" do
    let(:stage_type) { :runbook_step }
    let(:gate) { instance_double(Stages::WorkflowRunGate, call: Stages::WorkflowRunGate::Result.new(passed: true)) }

    before { allow(Stages::WorkflowRunGate).to receive(:new).and_return(gate) }

    it "starts the agent with the prompt as written" do
      handler.call

      expect(Stages::WorkflowRunGate).to have_received(:new).with(workflow: workflow, stage: stage, github: github)
      expect_run_started
    end

    it "wraps the prompt for message stages" do
      allow(stage).to receive(:run_message?).and_return(true)
      allow(prompt).to receive(:slack_message).with("the prompt").and_return("post this")
      handler.call

      expect_run_started("post this")
    end

    it "does nothing while the gate is not passed" do
      allow(gate).to receive(:call).and_return(Stages::WorkflowRunGate::Result.new(passed: false))
      handler.call

      expect(launcher).not_to have_received(:call)
      expect(workflow.reload.processing).to be false
    end
  end

  describe "pr_check" do
    let(:stage_type) { :pr_check }

    it "delegates to Stages::PrCheckRun, passing the launcher" do
      run = instance_double(Stages::PrCheckRun, call: nil)
      allow(Stages::PrCheckRun).to receive(:new).and_return(run)
      handler.call

      expect(Stages::PrCheckRun).to have_received(:new).with(
        hash_including(workflow: workflow, stage: stage, project: project, github: github, git: git,
                       handoff: handoff, prompt: prompt, start_ai_run: launcher)
      )
      expect(run).to have_received(:call)
    end
  end
end
