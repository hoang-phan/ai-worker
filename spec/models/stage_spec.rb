require "rails_helper"

RSpec.describe Stage, type: :model do
  let_tmpdir(:local_directory, "stage-spec")
  let(:project) { build_jira_project(repo_full_name: "org/repo", local_directory: local_directory) }
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
      run_history = instance_double(Stages::RunHistory)
      allow(stage).to receive(:run_history).and_return(run_history)

      { last_action: "failed", consecutive_failures: 2, resolving_conflicts?: true,
        completed_local_test_rounds: 3, completed_ci_rounds: 4, local_test_unfinished?: false }.each do |method, result|
        expect(run_history).to receive(method).and_return(result)

        expect(stage.public_send(method)).to eq(result)
      end
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
