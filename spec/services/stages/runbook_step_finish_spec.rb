require "rails_helper"

RSpec.describe Stages::RunbookStepFinish, type: :service do
  let_tmpdir(:local_directory, "runbook-step-finish-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_runbook_workflow(project, status: :implementing, **running_ai_run)
  end
  let(:stage) do
    build_runbook_stage(workflow, name: "Deploy", position: 1, run_mode: run_mode,
                        channel: channel, auto_advance: auto_advance)
  end
  let(:run_mode) { :agent }
  let(:channel) { nil }
  let(:auto_advance) { false }
  let(:enqueue) { spy("enqueue") }

  def finish(output)
    described_class.new(workflow: workflow, stage: stage, enqueue: enqueue).call(output)
  end

  it "finishes a non-message step and waits for Next" do
    finish("agent output")

    expect(workflow.reload).to have_attributes(status: "waiting", awaiting_next: true).and have_finished_ai_run
    expect(stage_actions(stage)).to eq(%w[stage_completed])
    expect(enqueue).not_to have_received(:call)
  end

  context "for a message step" do
    let(:run_mode) { :message }
    let(:channel) { "#deploys" }

    it "finishes after the agent confirms the message was posted" do
      finish("POSTED")

      expect(workflow.reload).to have_attributes(status: "waiting", awaiting_next: true)
      expect(stage_actions(stage)).to eq(%w[stage_completed message_sent])
    end

    it "fails without a POSTED marker" do
      expect { finish("agent output") }
        .to raise_error(AiCli::CommandError, "agent finished without confirming the Slack message was posted (no POSTED line)")

      expect(workflow.reload).to have_attributes(status: "implementing", processing: true)
      expect(stage_actions(stage)).to be_empty
    end
  end

  it "merges output variables into the workflow" do
    workflow.update!(variables: { "REGION" => "us-east-1" })

    finish("VAR: VERSION=1.2.3\nVAR: REGION=eu-west-1")

    expect(workflow.reload.variables).to eq("REGION" => "eu-west-1", "VERSION" => "1.2.3")
  end

  context "when auto-advancing" do
    let(:auto_advance) { true }
    let!(:next_stage) { build_runbook_stage(workflow, name: "Verify", position: 2) }

    before { workflow.update!(current_stage_id: stage.id) }

    it "advances to the next stage and enqueues the scheduler" do
      finish("agent output")

      expect(workflow.reload).to have_attributes(status: "implementing", current_stage_id: next_stage.id,
                                                  awaiting_next: false, auto_run: true)
      expect(stage_actions(stage)).to eq(%w[stage_completed advanced])
      expect(enqueue).to have_received(:call).with(workflow.id)
    end
  end
end
