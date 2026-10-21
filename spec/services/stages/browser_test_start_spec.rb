require "rails_helper"

RSpec.describe Stages::BrowserTestStart, type: :service do
  let(:project) { instance_double(Project) }
  let(:workflow) { instance_double(Workflow, branch_name: "feature-branch") }
  let(:prompt) { instance_double(Prompts::StagePrompt, body: "the prompt") }
  let(:git) { class_double(Git::BranchService, checkout_remote_branch!: nil) }
  let(:launcher) { spy("Stages::AiRunLauncher") }
  let(:run) do
    instance_double(AiCli::BrowserTestRun, mcp_config_path: "/tmp/mcp.json", env: { "TEST_USER" => "u" }, disallowed_tools: [ "Bash" ])
  end
  let(:unvalidated) { double("AiCli::BrowserTestRun", validate!: run) }
  let(:factory) { class_double(AiCli::BrowserTestRun, new: unvalidated) }

  def start(kind)
    described_class.new(workflow: workflow, project: project, kind: kind, prompt: prompt, git: git,
                        launcher: launcher, browser_run: factory).call
  end

  it "builds the run for the kind and launches with its MCP config, env and disallowed tools" do
    start(:uat)

    expect(factory).to have_received(:new).with(project, workflow, kind: :uat)
    expect(launcher).to have_received(:call)
      .with("the prompt", mcp_config: "/tmp/mcp.json", env: { "TEST_USER" => "u" }, disallowed_tools: [ "Bash" ])
  end

  it "does not touch git for uat" do
    start(:uat)

    expect(git).not_to have_received(:checkout_remote_branch!)
  end

  it "checks out the workflow branch for local before launching" do
    start(:local)

    expect(factory).to have_received(:new).with(project, workflow, kind: :local)
    expect(git).to have_received(:checkout_remote_branch!).with(project, "feature-branch")
    expect(launcher).to have_received(:call).once
  end

  it "propagates a validation error without checking out or launching" do
    allow(unvalidated).to receive(:validate!).and_raise(ArgumentError, "invalid")

    expect { start(:local) }.to raise_error(ArgumentError, "invalid")
    expect(git).not_to have_received(:checkout_remote_branch!)
    expect(launcher).not_to have_received(:call)
  end

  it "propagates a checkout error without launching" do
    allow(git).to receive(:checkout_remote_branch!).and_raise(Git::CommandError, "nope")

    expect { start(:local) }.to raise_error(Git::CommandError, "nope")
    expect(launcher).not_to have_received(:call)
  end
end
