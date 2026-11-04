require "rails_helper"

RSpec.describe Stage, type: :model do
  let_jira_project("stage-spec", repo_full_name: "org/repo")
  let(:workflow) { build_jira_workflow(project, jira_ticket: "STG-1", branch_name: "stg-1", status: :pending) }
  let(:stage) { workflow.stages.create!(stage_type: :pr_check) }

  describe "#removable?" do
    let(:runbook) { build_runbook_workflow(project, status: :implementing) }
    let(:current_stage) { build_runbook_stage(runbook, name: "Deploy", position: 1) }

    it "refuses the current stage after a runbook has started, but allows it while pending or when it is not current" do
      runbook.update!(current_stage_id: current_stage.id)

      expect(current_stage).not_to be_removable

      runbook.update!(status: :pending)
      expect(current_stage).to be_removable

      runbook.update!(status: :implementing, current_stage_id: nil)
      expect(current_stage).to be_removable
    end
  end

  describe "failure stage" do
    let(:review) { workflow.stages.find_by!(stage_type: :pr_check) }
    let(:implementation) { workflow.stages.find_by!(stage_type: :implementation) }

    it "accepts another pipeline stage of the same workflow, or the stage itself" do
      expect(review.update(failure_stage: implementation)).to be true
      expect(review.update(failure_stage: review)).to be true
    end

    it "rejects a stage of another workflow" do
      other = build_jira_workflow(project).stages.find_by!(stage_type: :pr_check)

      expect(review.update(failure_stage: other)).to be false
      expect(review.errors[:failure_stage_id]).to be_present
    end

    it "rejects a stage outside the pipeline" do
      jira = workflow.stages.create!(stage_type: :jira_update)

      expect(review.update(failure_stage: jira)).to be false
    end

    it "is cleared when the selected stage is destroyed" do
      review.update!(failure_stage: implementation)

      implementation.destroy!

      expect(review.reload.failure_stage_id).to be_nil
    end

    it "is only offered for the stage types that can fail" do
      expect(review).to be_failure_capable
      expect(implementation).not_to be_failure_capable
    end
  end

  describe "run history delegation" do
    it "orders actions by id descending, whatever created_at says" do
      stage.stage_runs.create!(action: "started")
      stage.stage_runs.create!(action: "failed")
      stage.stage_runs.find_by(action: "failed").update_columns(created_at: 1.day.ago)

      expect(stage.last_action).to eq("failed")
    end

    it "builds fresh history after logging a run" do
      expect(stage.last_action).to be_nil

      stage.log_run!("started")

      expect(stage.last_action).to eq("started")
    end

    it "forwards all run history methods" do
      stage.log_run!("failed")
      expect(stage.last_action).to eq("failed")

      stage.log_run!("failed")
      expect(stage.consecutive_failures).to eq(2)

      stage.log_run!("conflict_resolution_started")
      expect(stage).to be_resolving_conflicts

      3.times { stage.log_run!("local_test_completed") }
      expect(stage.completed_local_test_rounds).to eq(3)
      expect(stage).not_to be_local_test_unfinished

      4.times { stage.log_run!("ci_check_completed") }
      expect(stage.completed_ci_rounds).to eq(4)
    end
  end

  describe "#log_run!" do
    it "persists the action, output and error and returns the run" do
      run = stage.log_run!("failed", output: "some output", error: "boom")

      expect(run).to be_persisted
      expect(run.reload).to have_attributes(stage: stage, action: "failed", output: "some output", error: "boom")
    end

    it "leaves output and error nil by default" do
      run = stage.log_run!("started")

      expect(run).to have_attributes(action: "started", output: nil, error: nil)
    end

    it "raises RecordInvalid for an action outside StageRun::ACTIONS" do
      expect { stage.log_run!("not_a_real_action") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(stage.stage_runs.count).to eq(0)
    end
  end
end
