require "rails_helper"

RSpec.describe Stages::StartHandler, type: :service do
  let(:local_directory) { Dir.mktmpdir("start-handler-spec") }
  let(:project) do
    Project.create!(name: "Start handler #{SecureRandom.hex(4)}", kind: :jira,
                    repo_full_name: "acme/widgets", local_directory: local_directory)
  end
  let(:workflow) do
    project.workflows.create!(jira_ticket: "START-1", branch_name: "start-handler", github_reviewer: "octocat",
                              github_pr_url: "https://github.com/acme/widgets/pull/1", status: :implementing)
  end
  let(:stage_type) { :implementation }
  let(:stage) { workflow.stages.create!(stage_type: stage_type, name: stage_type.to_s) }
  let(:github) { double("Github::Client") }
  let(:git) { class_double(Git::BranchService, create_branch!: nil, checkout_remote_branch!: nil, update_with_main!: :updated) }
  let(:prompt) { instance_double(Prompts::StagePrompt, body: "the prompt") }
  let(:handoff) { double("Stages::ReviewHandoff", reviewers: [ "octocat" ]) }
  let(:browser_run) do
    instance_double(AiCli::BrowserTestRun, mcp_config_path: "/tmp/mcp.json", env: { "TEST_USER" => "u" }, disallowed_tools: [ "Bash" ])
  end

  def handler
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, git: git, prompt: prompt, handoff: handoff)
  end

  def actions = stage.stage_runs.reorder(:id).pluck(:action)

  before do
    allow(AiCli::RunLogs).to receive(:new_path).and_return("/tmp/start.log")
    allow(AiCli::Runner).to receive(:start).and_return(4242)
  end

  after do
    FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory)
  end

  def expect_run_started(action: "started", **options)
    expect(AiCli::Runner).to have_received(:start).with(local_directory, anything, hash_including(log_path: "/tmp/start.log", **options))
    expect(workflow.reload).to have_attributes(processing: true, ai_pid: 4242, ai_log_path: "/tmp/start.log", ai_log_offset: 0)
    expect(workflow.ai_started_at).to be_present
    expect(actions).to eq [ action ]
  end

  describe "#start_ai_run" do
    it "detaches the agent, records the run on the workflow and logs the action" do
      handler.start_ai_run("hello", action: "conflict_resolution_started")

      expect(AiCli::Runner).to have_received(:start).with(local_directory, "hello", log_path: "/tmp/start.log", mcp_config: nil, env: {}, disallowed_tools: [])
      expect_run_started(action: "conflict_resolution_started")
    end
  end

  describe "implementation" do
    it "creates the branch and starts the agent" do
      handler.call

      expect(git).to have_received(:create_branch!).with(project, "start-handler")
      expect(AiCli::Runner).to have_received(:start).with(local_directory, "the prompt", anything)
      expect_run_started
    end

    it "propagates a branch error without starting the agent" do
      allow(git).to receive(:create_branch!).and_raise(Git::CommandError, "nope")

      expect { handler.call }.to raise_error(Git::CommandError, "nope")
      expect(AiCli::Runner).not_to have_received(:start)
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

    it "checks out the head branch of a same-repo PR and starts the agent" do
      allow(github).to receive(:pr_info).and_return("state" => "OPEN", "head_ref" => "feature")
      handler.call

      expect(git).to have_received(:checkout_remote_branch!).with(project, "feature")
      expect_run_started
    end

    it "uses gh to check out a cross-repository PR" do
      allow(github).to receive(:pr_info).and_return("state" => "OPEN", "cross_repository" => true)
      allow(github).to receive(:checkout_pr!)
      handler.call

      expect(github).to have_received(:checkout_pr!).with(workflow.github_pr_url)
      expect(git).not_to have_received(:checkout_remote_branch!)
      expect_run_started
    end

    it "marks the workflow done and skips a PR that is not open" do
      allow(github).to receive(:pr_info).and_return("state" => "MERGED")
      handler.call

      expect(workflow.reload.status).to eq "done"
      expect(actions).to eq %w[pr_not_open_skipped]
      expect(AiCli::Runner).not_to have_received(:start)
    end
  end

  describe "uat_test" do
    let(:stage_type) { :uat_test }

    it "validates the browser run and starts the agent with its MCP config, env and disallowed tools" do
      allow(AiCli::BrowserTestRun).to receive(:new).with(project, workflow, kind: :uat).and_return(double(validate!: browser_run))
      handler.call

      expect_run_started(mcp_config: "/tmp/mcp.json", env: { "TEST_USER" => "u" }, disallowed_tools: [ "Bash" ])
    end

    it "propagates a validation error" do
      invalid = double("AiCli::BrowserTestRun")
      allow(invalid).to receive(:validate!).and_raise(ArgumentError, "no uat")
      allow(AiCli::BrowserTestRun).to receive(:new).and_return(invalid)

      expect { handler.call }.to raise_error(ArgumentError, "no uat")
      expect(AiCli::Runner).not_to have_received(:start)
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

  describe "runbook_step" do
    let(:stage_type) { :runbook_step }
    let(:gate) { instance_double(Stages::WorkflowRunGate, call: Stages::WorkflowRunGate::Result.new(passed: true)) }

    before { allow(Stages::WorkflowRunGate).to receive(:new).and_return(gate) }

    it "starts the agent with the prompt as written" do
      handler.call

      expect(Stages::WorkflowRunGate).to have_received(:new).with(workflow: workflow, stage: stage, github: github)
      expect(AiCli::Runner).to have_received(:start).with(local_directory, "the prompt", anything)
      expect_run_started
    end

    it "wraps the prompt for message stages" do
      allow(stage).to receive(:run_message?).and_return(true)
      allow(prompt).to receive(:slack_message).with("the prompt").and_return("post this")
      handler.call

      expect(AiCli::Runner).to have_received(:start).with(local_directory, "post this", anything)
    end

    it "does nothing while the gate is not passed" do
      allow(gate).to receive(:call).and_return(Stages::WorkflowRunGate::Result.new(passed: false))
      handler.call

      expect(AiCli::Runner).not_to have_received(:start)
      expect(workflow.reload.processing).to be false
    end
  end

  describe "pr_check" do
    let(:stage_type) { :pr_check }

    it "delegates to Stages::PrCheckRun, passing start_ai_run" do
      run = instance_double(Stages::PrCheckRun, call: nil)
      allow(Stages::PrCheckRun).to receive(:new).and_return(run)
      handler.call

      expect(Stages::PrCheckRun).to have_received(:new).with(
        hash_including(workflow: workflow, stage: stage, project: project, github: github, git: git,
                       handoff: handoff, prompt: prompt, start_ai_run: an_instance_of(Method))
      )
      expect(run).to have_received(:call)
    end
  end
end
