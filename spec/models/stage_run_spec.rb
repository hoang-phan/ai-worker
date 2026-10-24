require "rails_helper"

RSpec.describe StageRun, type: :model do
  subject(:stage_run) { described_class.new(action: action) }

  let(:action) { "started" }

  describe "ACTIONS" do
    it "has no duplicates" do
      expect(described_class::ACTIONS.uniq).to eq(described_class::ACTIONS)
    end
  end

  describe "action validation" do
    context "when the action is nil" do
      let(:action) { nil }

      it "is required" do
        stage_run.valid?

        expect(stage_run.errors[:action]).to include("can't be blank")
      end
    end

    context "when the action is not in ACTIONS" do
      let(:action) { "not_a_real_action" }

      it "is rejected" do
        stage_run.valid?

        expect(stage_run.errors[:action]).to include("is not included in the list")
      end
    end

    StageRun::ACTIONS.each do |known_action|
      context "when the action is #{known_action}" do
        let(:action) { known_action }

        it "is accepted" do
          stage_run.valid?

          expect(stage_run.errors[:action]).to be_empty
        end
      end
    end
  end

  describe ".history_for" do
    let_jira_project("stage-run-spec", repo_full_name: "org/repo")
    let(:workflow) { build_jira_workflow(project, jira_ticket: "SR-1", branch_name: "sr-1", status: :pending) }
    let(:other_workflow) { build_jira_workflow(project, jira_ticket: "SR-2", branch_name: "sr-2", status: :pending) }
    let(:other_project_workflow) do
      other_project = build_jira_project(repo_full_name: "org/other", local_directory: local_directory)
      build_jira_workflow(other_project, jira_ticket: "SR-1", branch_name: "sr-1", status: :pending)
    end

    it "returns only runs belonging to the workflow, across its stages" do
      workflow.stages.create!(stage_type: :pr_check) if workflow.stages.count < 2
      mine = workflow.stages.map { |stage| stage.stage_runs.create!(action: "started") }
      other_workflow.stages.first.stage_runs.create!(action: "failed")
      other_project_workflow.stages.first.stage_runs.create!(action: "halted")

      expect(described_class.history_for(workflow)).to match_array(mine)
    end

    it "orders newest first and breaks created_at ties by id descending" do
      stage = workflow.stages.first
      now = Time.current.change(usec: 0)
      oldest = stage.stage_runs.create!(action: "started", created_at: now - 1.hour)
      tie_first = stage.stage_runs.create!(action: "resumed", created_at: now)
      tie_second = stage.stage_runs.create!(action: "failed", created_at: now)

      expect(described_class.history_for(workflow).to_a).to eq([ tie_second, tie_first, oldest ])
    end
  end
end
