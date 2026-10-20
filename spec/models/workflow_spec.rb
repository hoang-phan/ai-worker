require "rails_helper"

RSpec.describe Workflow, type: :model do
  let(:local_directory) { Dir.mktmpdir("workflow-spec") }
  let(:project) { Project.create!(name: "Spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }
  let(:pr_url) { "https://github.com/org/repo/pull/7" }
  let(:workflow) do
    project.workflows.create!(jira_ticket: "SPEC-1", branch_name: "spec-1", github_reviewer: "someone", status: :pending)
  end

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  def stage_run_actions(stage)
    stage.stage_runs.reorder(:id).pluck(:action)
  end

  describe "#start!" do
    it "moves a pending development workflow to implementing" do
      expect(workflow.start!).to be true
      expect(workflow.reload).to be_implementing
    end

    it "starts a runbook at its first stage" do
      runbook = project.workflows.create!(kind: :runbook)
      first = runbook.stages.create!(stage_type: :runbook_step, name: "One", position: 1)
      expect(runbook.start!).to be true
      expect(runbook.reload).to be_implementing
      expect(runbook.current_stage_id).to eq(first.id)
    end

    it "finishes a runbook without stages" do
      runbook = project.workflows.create!(kind: :runbook)
      expect(runbook.start!).to be true
      expect(runbook.reload).to be_done
    end

    it "refuses a workflow that is already started" do
      workflow.update!(status: :reviewing)
      expect(workflow.start!).to be false
      expect(workflow.reload).to be_reviewing
    end
  end

  describe "#request_stage_run!" do
    let(:runbook) { project.workflows.create!(kind: :runbook, status: :implementing) }

    it "flags auto_run on an idle implementing runbook" do
      expect(runbook).to be_can_run_stage
      expect(runbook.request_stage_run!).to be true
      expect(runbook.reload.auto_run).to be true
    end

    it "refuses while a stage is processing" do
      runbook.update!(processing: true)
      expect(runbook.request_stage_run!).to be false
      expect(runbook.reload.auto_run).to be false
    end

    it "refuses a runbook that is not implementing" do
      runbook.update!(status: :pending)
      expect(runbook.request_stage_run!).to be false
    end

    it "refuses a development workflow" do
      workflow.update!(status: :implementing)
      expect(workflow).not_to be_can_run_stage
      expect(workflow.request_stage_run!).to be false
      expect(workflow.reload.auto_run).to be false
    end
  end

  describe "#can_advance?" do
    it "is true only for a runbook awaiting Next" do
      runbook = project.workflows.create!(kind: :runbook, status: :implementing)
      expect(runbook).not_to be_can_advance
      runbook.update!(awaiting_next: true)
      expect(runbook).to be_can_advance
      workflow.update!(awaiting_next: true)
      expect(workflow).not_to be_can_advance
    end
  end

  describe "#resume!" do
    before { workflow.update!(status: :errored) }

    it "refuses a workflow that is not errored" do
      workflow.update!(status: :reviewing)
      expect { expect(workflow.resume!).to be false }.not_to change(StageRun, :count)
      expect(workflow.reload).to be_reviewing
    end

    it "goes back to implementing without a PR and logs 'resumed' on the implementation stage" do
      expect(workflow.resume!).to be true
      expect(workflow.reload).to be_implementing
      expect(stage_run_actions(workflow.stages.find_by(stage_type: :implementation))).to eq(%w[resumed])
    end

    it "goes back to reviewing once a PR exists and logs 'resumed' on the pr_check stage" do
      workflow.update!(github_pr_url: pr_url)
      expect(workflow.resume!).to be true
      expect(workflow.reload).to be_reviewing
      expect(stage_run_actions(workflow.stages.find_by(stage_type: :pr_check))).to eq(%w[resumed])
    end

    it "goes back to uat_testing when a UAT test was scheduled" do
      workflow.update!(github_pr_url: pr_url, uat_test_at: 1.hour.ago)
      expect(workflow.resume!).to be true
      expect(workflow.reload).to be_uat_testing
      expect(stage_run_actions(workflow.stages.find_by(stage_type: :uat_test))).to eq(%w[resumed])
    end

    it "goes back to local_testing when the last local test run never finished" do
      workflow.update!(github_pr_url: pr_url)
      local = workflow.stages.create!(stage_type: :local_test)
      local.stage_runs.create!(action: "local_test_failing")
      expect(workflow.resume!).to be true
      expect(workflow.reload).to be_local_testing
      expect(stage_run_actions(local)).to eq(%w[local_test_failing resumed])
    end

    it "returns to reviewing when the last local test run completed" do
      workflow.update!(github_pr_url: pr_url)
      local = workflow.stages.create!(stage_type: :local_test)
      local.stage_runs.create!(action: "local_test_completed")
      expect(workflow.resume!).to be true
      expect(workflow.reload).to be_reviewing
    end

    it "resumes a runbook on its current stage" do
      runbook = project.workflows.create!(kind: :runbook)
      step = runbook.stages.create!(stage_type: :runbook_step, name: "One", position: 1)
      runbook.update!(status: :errored, current_stage_id: step.id)
      expect(runbook.resume!).to be true
      expect(runbook.reload).to be_implementing
      expect(stage_run_actions(step)).to eq(%w[resumed])
    end
  end

  describe "#rollback_to_review!" do
    before { workflow.update!(status: :done, github_pr_url: pr_url) }

    it "sends a done development workflow with a PR back to reviewing and logs the StageRun" do
      expect(workflow.rollback_to_review!).to be true
      expect(workflow.reload).to be_reviewing
      expect(stage_run_actions(workflow.stages.find_by(stage_type: :pr_check))).to eq(%w[rolled_back_to_review])
    end

    it "refuses without a PR" do
      workflow.update!(github_pr_url: nil)
      expect { expect(workflow.rollback_to_review!).to be false }.not_to change(StageRun, :count)
      expect(workflow.reload).to be_done
    end

    it "refuses when not done" do
      workflow.update!(status: :errored)
      expect(workflow.rollback_to_review!).to be false
      expect(workflow.reload).to be_errored
    end

    it "refuses a runbook" do
      runbook = project.workflows.create!(kind: :runbook, status: :done, github_pr_url: pr_url)
      expect(runbook.rollback_to_review!).to be false
      expect(runbook.reload).to be_done
    end
  end

  describe "AI_RUN_RESET" do
    it "covers processing and every ai_* column" do
      expected = Workflow.column_names.grep(/\Aai_/) + %w[processing]
      expect(Workflow::AI_RUN_RESET.keys.map(&:to_s)).to match_array(expected)
    end
  end
end
