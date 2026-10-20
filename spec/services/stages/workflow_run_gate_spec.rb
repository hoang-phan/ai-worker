require "rails_helper"

RSpec.describe Stages::WorkflowRunGate, type: :service do
  let(:project) { Project.create!(name: "Gate #{SecureRandom.hex(4)}", kind: :jira, repo_full_name: "acme/widgets", local_directory: "/tmp/gate-spec") }
  let(:workflow) { project.workflows.create!(kind: :runbook, status: :implementing, variables: { "REPO" => "acme/other" }) }
  let!(:previous) { workflow.stages.create!(stage_type: :runbook_step, name: "One", position: 1) }
  let(:wait_for) { "deploy.yml" }
  let!(:stage) { workflow.stages.create!(stage_type: :runbook_step, name: "Two", position: 2, wait_for_workflow: wait_for) }
  let(:github) { instance_double(Github::Client) }

  before { workflow.update!(current_stage_id: stage.id) }

  def gate = described_class.new(workflow: workflow, stage: stage, github: github)

  context "with a blank wait_for_workflow" do
    let(:wait_for) { nil }

    it "passes without calling GitHub or logging" do
      expect(github).not_to receive(:workflow_run_state)

      expect(gate.call).to be_passed
      expect(stage.stage_runs).to be_empty
    end
  end

  it "passes on success and logs check_passed with the url" do
    allow(github).to receive(:workflow_run_state).and_return(state: :success, url: "u1", conclusion: "success")

    expect(gate.call).to be_passed
    expect(stage.stage_runs.where(action: "check_passed").sole.output).to eq("u1")
  end

  %i[pending none].each do |state|
    it "waits on #{state} and logs waiting_for_check only once" do
      allow(github).to receive(:workflow_run_state).and_return({ state: state, url: "u1" })

      expect(gate.call).not_to be_passed
      expect(gate.call).not_to be_passed
      expect(stage.stage_runs.where(action: "waiting_for_check").count).to eq(1)
    end
  end

  it "does not log again when the last action is already waiting_for_check" do
    stage.stage_runs.create!(action: "waiting_for_check")
    allow(github).to receive(:workflow_run_state).and_return(state: :pending, url: "u1")

    expect(gate.call).not_to be_passed
    expect(stage.stage_runs.count).to eq(1)
  end

  it "raises with the conclusion and url when the run failed" do
    allow(github).to receive(:workflow_run_state).and_return(state: :failed, url: "u1", conclusion: "cancelled")

    expect { gate.call }.to raise_error(Github::CommandError, "GitHub Actions deploy.yml finished with cancelled: u1")
  end

  describe "since" do
    before { allow(github).to receive(:workflow_run_state).and_return(state: :pending) }

    it "is the previous stage's latest started run" do
      older = previous.stage_runs.create!(action: "started", created_at: 3.hours.ago)
      newest = previous.stage_runs.create!(action: "started", created_at: 1.hour.ago)
      previous.stage_runs.create!(action: "failed", created_at: 10.minutes.ago)

      gate.call

      expect(older).to be_present
      expect(github).to have_received(:workflow_run_state).with("deploy.yml", since: newest.created_at, repo: "acme/other")
    end

    it "falls back to the workflow's created_at" do
      gate.call

      expect(github).to have_received(:workflow_run_state).with("deploy.yml", since: workflow.created_at, repo: "acme/other")
    end
  end
end
