require "rails_helper"

RSpec.describe Workflows::Transitions do
  let_jira_project("transitions-spec", repo_full_name: "org/repo")
  let(:pr_url) { "https://github.com/org/repo/pull/7" }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "SPEC-1", branch_name: "spec-1", status: :pending)
  end
  let(:transitions) { described_class.new(workflow) }

  def transitions_for(record)
    described_class.new(record)
  end

  describe "#start!" do
    it "moves a pending development workflow to implementing, on its first stage" do
      expect(transitions.start!).to be true
      expect(workflow.reload).to be_implementing
      expect(workflow.current_stage_id).to eq workflow.stages.find_by!(stage_type: :implementation).id
    end

    it "starts a ci_loop workflow at its first stage in the pipeline order" do
      ci = build_ci_workflow(build_ci_project(name: "start-ci-spec", repo_full_name: "org/repo"), status: :pending)
      expect(Workflows::Transitions.new(ci).start!).to be true
      expect(ci.reload).to have_attributes(status: "implementing", current_stage_id: ci.stages.find_by!(stage_type: :simple_implementation).id)
    end

    it "starts a runbook at its first stage" do
      runbook = build_runbook_workflow(project)
      first = build_runbook_stage(runbook, name: "One", position: 1)
      expect(Workflows::Transitions.new(runbook).start!).to be true
      expect(runbook.reload).to be_implementing
      expect(runbook.current_stage_id).to eq(first.id)
    end

    it "finishes a runbook without stages" do
      runbook = build_runbook_workflow(project)
      expect(Workflows::Transitions.new(runbook).start!).to be true
      expect(runbook.reload).to be_done
    end

    it "refuses a workflow that is already started" do
      workflow.update!(status: :reviewing)
      expect(transitions.start!).to be false
      expect(workflow.reload).to be_reviewing
    end
  end

  describe "#skip_stage!" do
    let(:ci_project) { build_ci_project(name: "skip-stage-spec", repo_full_name: "org/repo") }
    let(:ci_workflow) { build_ci_workflow(ci_project, status: :ci_checking, ci_output_path: "/tmp/old.log", ci_exit_status: 1) }

    it "moves the check on to verify, clearing the stale check output" do
      stage = ci_workflow.current_stage
      expect(transitions_for(ci_workflow).skip_stage!).to be true

      ci_workflow.reload
      expect(ci_workflow).to be_ci_verifying
      expect(ci_workflow.current_stage_id).to eq ci_workflow.stages.find_by!(stage_type: :ci_verify).id
      expect(ci_workflow.ci_output_path).to be_nil
      expect(ci_workflow.ci_exit_status).to be_nil
      expect(stage.stage_runs.pluck(:action)).to eq(%w[stage_skipped])
    end

    it "moves verify on to review" do
      ci_workflow.update!(status: :ci_verifying)
      expect(transitions_for(ci_workflow).skip_stage!).to be true
      expect(ci_workflow.reload).to be_reviewing
    end

    it "refuses while an agent run is in flight" do
      ci_workflow.update!(processing: true)
      expect(transitions_for(ci_workflow).skip_stage!).to be false
      expect(ci_workflow.reload).to be_ci_checking
    end

    it "refuses outside the check and verify stages" do
      ci_workflow.update!(status: :reviewing)
      expect(transitions_for(ci_workflow).skip_stage!).to be false
    end

    it "refuses on a project without the ci_loop flow" do
      expect(transitions_for(workflow.tap { |w| w.update!(status: :ci_checking) }).skip_stage!).to be false
    end
  end

  describe "#request_stage_run!" do
    let(:runbook) { build_runbook_workflow(project, status: :implementing) }

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
      runbook = build_runbook_workflow(project, status: :implementing)
      expect(transitions_for(runbook)).not_to be_can_advance
      runbook.update!(awaiting_next: true)
      expect(transitions_for(runbook)).to be_can_advance
      workflow.update!(awaiting_next: true)
      expect(transitions).not_to be_can_advance
    end
  end

  describe "#rollback_to_review!" do
    before { workflow.update!(status: :done, github_pr_url: pr_url) }

    it "sends a done development workflow with a PR back to reviewing and logs the StageRun" do
      expect(transitions.rollback_to_review!).to be true
      expect(workflow.reload).to be_reviewing
      expect(stage_actions(workflow.stages.find_by(stage_type: :pr_check))).to eq(%w[rolled_back_to_review])
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
      runbook = build_runbook_workflow(project, status: :done, github_pr_url: pr_url)
      expect(Workflows::Transitions.new(runbook).rollback_to_review!).to be false
      expect(runbook.reload).to be_done
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
