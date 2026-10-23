require "rails_helper"

RSpec.describe Workflows::Transitions do
  let_tmpdir(:local_directory, "transitions-spec")
  let(:project) { Project.create!(name: "Transitions spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }
  let(:pr_url) { "https://github.com/org/repo/pull/7" }
  let(:workflow) do
    project.workflows.create!(jira_ticket: "SPEC-1", branch_name: "spec-1", github_reviewer: "someone", status: :pending)
  end
  let(:transitions) { described_class.new(workflow) }

  def transitions_for(record)
    described_class.new(record)
  end

  def stage_run_actions(stage)
    stage.stage_runs.reorder(:id).pluck(:action)
  end

  describe "#start!" do
    it "moves a pending development workflow to implementing" do
      expect(transitions.start!).to be true
      expect(workflow.reload).to be_implementing
    end

    it "starts a runbook at its first stage" do
      runbook = project.workflows.create!(kind: :runbook)
      first = runbook.stages.create!(stage_type: :runbook_step, name: "One", position: 1)
      expect(Workflows::Transitions.new(runbook).start!).to be true
      expect(runbook.reload).to be_implementing
      expect(runbook.current_stage_id).to eq(first.id)
    end

    it "finishes a runbook without stages" do
      runbook = project.workflows.create!(kind: :runbook)
      expect(Workflows::Transitions.new(runbook).start!).to be true
      expect(runbook.reload).to be_done
    end

    it "refuses a workflow that is already started" do
      workflow.update!(status: :reviewing)
      expect(transitions.start!).to be false
      expect(workflow.reload).to be_reviewing
    end
  end

  describe "#request_stage_run!" do
    let(:runbook) { project.workflows.create!(kind: :runbook, status: :implementing) }

    it "flags auto_run on an idle implementing runbook" do
      expect(transitions_for(runbook)).to be_can_run_stage
      expect(Workflows::Transitions.new(runbook).request_stage_run!).to be true
      expect(runbook.reload.auto_run).to be true
    end

    it "refuses while a stage is processing" do
      runbook.update!(processing: true)
      expect(Workflows::Transitions.new(runbook).request_stage_run!).to be false
      expect(runbook.reload.auto_run).to be false
    end

    it "refuses a runbook that is not implementing" do
      runbook.update!(status: :pending)
      expect(Workflows::Transitions.new(runbook).request_stage_run!).to be false
    end

    it "refuses a development workflow" do
      workflow.update!(status: :implementing)
      expect(transitions).not_to be_can_run_stage
      expect(transitions.request_stage_run!).to be false
      expect(workflow.reload.auto_run).to be false
    end
  end

  describe "#can_advance?" do
    it "is true only for a runbook awaiting Next" do
      runbook = project.workflows.create!(kind: :runbook, status: :implementing)
      expect(transitions_for(runbook)).not_to be_can_advance
      runbook.update!(awaiting_next: true)
      expect(transitions_for(runbook)).to be_can_advance
      workflow.update!(awaiting_next: true)
      expect(transitions).not_to be_can_advance
    end
  end

  describe "#resume!" do
    before { workflow.update!(status: :errored) }

    it "refuses a workflow that is not errored" do
      workflow.update!(status: :reviewing)
      expect { expect(transitions.resume!).to be false }.not_to change(StageRun, :count)
      expect(workflow.reload).to be_reviewing
    end

    it "uses ResumeStatus and logs one 'resumed' StageRun on the resulting current stage" do
      workflow.update!(github_pr_url: pr_url)
      resume_status = instance_double(Workflows::ResumeStatus, call: :reviewing)
      allow(Workflows::ResumeStatus).to receive(:new).with(workflow).and_return(resume_status)

      expect { expect(transitions.resume!).to be true }.to change(StageRun, :count).by(1)
      expect(workflow.reload).to be_reviewing
      expect(stage_run_actions(workflow.stages.find_by(stage_type: :pr_check))).to eq(%w[resumed])
    end

    it "updates a runbook and logs one 'resumed' StageRun on its current stage" do
      runbook = project.workflows.create!(kind: :runbook)
      step = runbook.stages.create!(stage_type: :runbook_step, name: "One", position: 1)
      runbook.update!(status: :errored, current_stage_id: step.id)
      expect { expect(Workflows::Transitions.new(runbook).resume!).to be true }.to change(StageRun, :count).by(1)
      expect(runbook.reload).to be_implementing
      expect(stage_run_actions(step)).to eq(%w[resumed])
    end
  end

  describe "#rollback_to_review!" do
    before { workflow.update!(status: :done, github_pr_url: pr_url) }

    it "sends a done development workflow with a PR back to reviewing and logs the StageRun" do
      expect(transitions.rollback_to_review!).to be true
      expect(workflow.reload).to be_reviewing
      expect(stage_run_actions(workflow.stages.find_by(stage_type: :pr_check))).to eq(%w[rolled_back_to_review])
    end

    it "refuses without a PR" do
      workflow.update!(github_pr_url: nil)
      expect { expect(transitions.rollback_to_review!).to be false }.not_to change(StageRun, :count)
      expect(workflow.reload).to be_done
    end

    it "refuses when not done" do
      workflow.update!(status: :errored)
      expect(transitions.rollback_to_review!).to be false
      expect(workflow.reload).to be_errored
    end

    it "refuses a runbook" do
      runbook = project.workflows.create!(kind: :runbook, status: :done, github_pr_url: pr_url)
      expect(Workflows::Transitions.new(runbook).rollback_to_review!).to be false
      expect(runbook.reload).to be_done
    end
  end

  describe "#resume_status" do
    it "forwards to ResumeStatus" do
      resume_status = instance_double(Workflows::ResumeStatus, call: :reviewing)
      allow(Workflows::ResumeStatus).to receive(:new).with(workflow).and_return(resume_status)

      expect(transitions.resume_status).to eq(:reviewing)
    end
  end

  describe "#can_rollback_to_review?" do
    it "is true only for a done development workflow with a PR" do
      workflow.update!(status: :done)
      expect(transitions).not_to be_can_rollback_to_review
      workflow.update!(github_pr_url: pr_url)
      expect(transitions).to be_can_rollback_to_review
    end
  end
end
