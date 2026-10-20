require "rails_helper"

RSpec.describe Stage, type: :model do
  let(:local_directory) { Dir.mktmpdir("stage-spec") }
  let(:project) { Project.create!(name: "Stage spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }
  let(:workflow) { project.workflows.create!(jira_ticket: "STG-1", branch_name: "stg-1", github_reviewer: "someone", status: :pending) }
  let(:stage) { workflow.stages.create!(stage_type: :pr_check) }

  after { FileUtils.remove_entry(local_directory) if File.exist?(local_directory) }

  def add_runs(target, *actions)
    actions.each { |action| target.stage_runs.create!(action: action) }
  end

  describe "#removable?" do
    let(:runbook) { project.workflows.create!(kind: :runbook, status: :implementing) }
    let(:current_stage) { runbook.stages.create!(stage_type: :runbook_step, name: "Deploy", position: 1) }

    it "refuses the current stage after a runbook has started, but allows it while pending or when it is not current" do
      runbook.update!(current_stage_id: current_stage.id)

      expect(current_stage).not_to be_removable

      runbook.update!(status: :pending)
      expect(current_stage).to be_removable

      runbook.update!(status: :implementing, current_stage_id: nil)
      expect(current_stage).to be_removable
    end
  end

  describe "#last_action" do
    it "is nil without runs" do
      expect(stage.last_action).to be_nil
    end

    it "is the newest run's action by id, whatever created_at says" do
      add_runs(stage, "started", "failed")
      stage.stage_runs.find_by(action: "failed").update_columns(created_at: 1.day.ago)

      expect(stage.last_action).to eq("failed")
    end
  end

  describe "#consecutive_failures" do
    it "is 0 without runs" do
      expect(stage.consecutive_failures).to eq(0)
    end

    it "counts trailing failed runs, ignoring started ones between them" do
      add_runs(stage, "started", "failed", "started", "failed")

      expect(stage.consecutive_failures).to eq(2)
    end

    it "stops at a resumed run" do
      add_runs(stage, "failed", "failed", "resumed", "started", "failed")

      expect(stage.consecutive_failures).to eq(1)
    end

    it "stops at a success" do
      add_runs(stage, "failed", "ran_implementation", "started")

      expect(stage.consecutive_failures).to eq(0)
    end
  end

  describe "#resolving_conflicts?" do
    it "is false without runs" do
      expect(stage).not_to be_resolving_conflicts
    end

    it "is true when the conflict marker is the last action" do
      add_runs(stage, "started", "conflict_resolution_started")

      expect(stage).to be_resolving_conflicts
    end

    it "is false when the marker is an earlier action" do
      add_runs(stage, "conflict_resolution_started", "conflicts_resolved", "started")

      expect(stage).not_to be_resolving_conflicts
    end
  end

  describe "#completed_local_test_rounds" do
    let(:stage) { workflow.stages.create!(stage_type: :local_test) }

    it "is 0 without runs" do
      expect(stage.completed_local_test_rounds).to eq(0)
    end

    it "counts only completed rounds" do
      add_runs(stage, "started", "local_test_completed", "local_test_failing", "started", "local_test_completed", "started")

      expect(stage.completed_local_test_rounds).to eq(2)
    end
  end

  describe "#local_test_unfinished?" do
    let(:stage) { workflow.stages.create!(stage_type: :local_test) }

    it "is false without runs" do
      expect(stage).not_to be_local_test_unfinished
    end

    it "is true when the newest run is not a completion" do
      add_runs(stage, "started", "local_test_completed", "started")

      expect(stage).to be_local_test_unfinished
    end

    it "is false when the newest run is a completion" do
      add_runs(stage, "started", "local_test_completed")

      expect(stage).not_to be_local_test_unfinished
    end
  end
end
