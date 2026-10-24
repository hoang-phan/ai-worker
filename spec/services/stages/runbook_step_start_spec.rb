require "rails_helper"

RSpec.describe Stages::RunbookStepStart, type: :service do
  let(:project) { build_jira_project }
  let(:workflow) { build_runbook_workflow(project) }
  let(:stage) { build_runbook_stage(workflow) }
  let(:github) { double("Github::Client") }
  let(:prompt) { instance_double(Prompts::StagePrompt, body: "the prompt") }
  let(:launcher) { spy("Stages::AiRunLauncher") }
  let(:gate) { instance_double(Stages::WorkflowRunGate, call: Stages::WorkflowRunGate::Result.new(passed: true)) }

  before { allow(Stages::WorkflowRunGate).to receive(:new).and_return(gate) }

  def start
    described_class.new(workflow: workflow, stage: stage, github: github, prompt: prompt, launcher: launcher).call
  end

  it "starts the agent with the prompt as written" do
    start

    expect(Stages::WorkflowRunGate).to have_received(:new).with(workflow: workflow, stage: stage, github: github)
    expect(launcher).to have_received(:call).with("the prompt")
  end

  it "wraps the prompt for message stages" do
    allow(stage).to receive(:run_message?).and_return(true)
    allow(prompt).to receive(:slack_message).with("the prompt").and_return("post this")

    start

    expect(launcher).to have_received(:call).with("post this")
  end

  it "does nothing while the gate is not passed" do
    allow(gate).to receive(:call).and_return(Stages::WorkflowRunGate::Result.new(passed: false))

    start

    expect(launcher).not_to have_received(:call)
    expect(workflow.reload.processing).to be false
  end
end
