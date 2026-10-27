require "rails_helper"

RSpec.describe Stages::RunbookStepStart, type: :service do
  let(:project) { build_jira_project }
  let(:workflow) { build_runbook_workflow(project) }
  let(:stage) { build_runbook_stage(workflow) }
  let(:github) { instance_double(Github::Client) }
  let(:prompt) { instance_double(Prompts::StagePrompt, body: "the prompt") }
  let(:launcher) { spy("Stages::AiRunLauncher") }

  def start
    described_class.new(workflow: workflow, stage: stage, github: github, prompt: prompt, launcher: launcher).call
  end

  it "starts the agent with the prompt as written" do
    start

    expect(launcher).to have_received(:call).with("the prompt")
  end

  it "wraps the prompt for message stages" do
    stage.update!(run_mode: :message, channel: "#deploys")
    allow(prompt).to receive(:slack_message).with("the prompt").and_return("post this")

    start

    expect(launcher).to have_received(:call).with("post this")
  end

  context "when waiting for a workflow run" do
    let(:stage) { build_runbook_stage(workflow, wait_for_workflow: "deploy.yml") }
    let(:run_url) { "https://github.com/acme/repo/actions/runs/1" }

    it "does nothing while the check is pending" do
      allow(github).to receive(:workflow_run_state).and_return(state: :pending, url: run_url)

      start

      expect(github).to have_received(:workflow_run_state).with(
        "deploy.yml", since: workflow.created_at, repo: nil
      )
      expect(launcher).not_to have_received(:call)
      expect(stage.stage_runs.where(action: "waiting_for_check").sole.output).to eq(run_url)
      expect(workflow.reload.processing).to be false
    end

    it "launches once the check passes" do
      allow(github).to receive(:workflow_run_state).and_return(state: :success, url: run_url)

      start

      expect(launcher).to have_received(:call).with("the prompt")
      expect(stage.stage_runs.where(action: "check_passed").sole.output).to eq(run_url)
    end
  end
end
