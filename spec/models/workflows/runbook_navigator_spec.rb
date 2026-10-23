require "rails_helper"

RSpec.describe Workflows::RunbookNavigator do
  let_tmpdir(:local_directory, "runbook-navigator-spec")
  let(:project) { Project.create!(name: "Navigator spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }
  let(:workflow) { project.workflows.create!(kind: :runbook, status: :pending) }
  let(:navigator) { described_class.new(workflow) }

  def add_stage(name, position)
    workflow.stages.create!(stage_type: :runbook_step, name: name, position: position)
  end

  describe "#start!" do
    it "finishes a runbook without stages" do
      navigator.start!

      expect(workflow.reload).to be_done
    end

    it "starts at the first stage" do
      first = add_stage("One", 1)
      add_stage("Two", 2)
      workflow.update!(awaiting_next: true, auto_run: true)

      navigator.start!

      workflow.reload
      expect(workflow).to be_implementing
      expect(workflow.current_stage_id).to eq(first.id)
      expect(workflow.awaiting_next).to be false
      expect(workflow.auto_run).to be false
    end
  end

  describe "#advance!" do
    let!(:first) { add_stage("One", 1) }
    let!(:second) { add_stage("Two", 2) }

    before { workflow.update!(status: :implementing, current_stage_id: first.id, awaiting_next: true) }

    it "moves to the next stage with auto_run and logs an advanced run" do
      navigator.advance!

      workflow.reload
      expect(workflow.current_stage_id).to eq(second.id)
      expect(workflow).to be_implementing
      expect(workflow.awaiting_next).to be false
      expect(workflow.auto_run).to be true
      expect(first.stage_runs.pluck(:action)).to eq(%w[advanced])
    end

    it "finishes the workflow after the last stage" do
      workflow.update!(current_stage_id: second.id)

      navigator.advance!

      workflow.reload
      expect(workflow).to be_done
      expect(workflow.awaiting_next).to be false
      expect(workflow.auto_run).to be false
      expect(second.stage_runs.pluck(:action)).to eq(%w[advanced])
    end

    it "raises when the workflow is not waiting for Next" do
      workflow.update!(awaiting_next: false)

      expect { navigator.advance! }.to raise_error(ArgumentError, "workflow is not waiting for Next")
    end
  end

  describe "#next_stage and #previous_stage" do
    let!(:first) { add_stage("One", 1) }
    let!(:second) { add_stage("Two", 2) }
    let!(:third) { add_stage("Three", 3) }

    it "at the first stage" do
      workflow.update!(current_stage_id: first.id)

      expect(navigator.next_stage).to eq(second)
      expect(navigator.previous_stage).to be_nil
    end

    it "at a middle stage" do
      workflow.update!(current_stage_id: second.id)

      expect(navigator.next_stage).to eq(third)
      expect(navigator.previous_stage).to eq(first)
    end

    it "at the last stage" do
      workflow.update!(current_stage_id: third.id)

      expect(navigator.next_stage).to be_nil
      expect(navigator.previous_stage).to eq(second)
    end

    it "without a current stage" do
      expect(navigator.next_stage).to eq(first)
      expect(navigator.previous_stage).to be_nil
    end
  end
end
