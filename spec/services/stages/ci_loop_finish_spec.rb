require "rails_helper"

RSpec.describe "check/verify loop finish handlers", type: :service do
  let(:project) { build_ci_project(ci_max_rounds: 2) }
  let(:workflow) do
    build_ci_workflow(project, status: :ci_verifying, processing: true, ai_pid: 1, ai_log_path: "/tmp/x.log", ai_started_at: Time.current)
  end
  let(:github) { double("Github::Client", find_pr_url: "https://github.com/acme/widgets/pull/9") }
  let(:handoff) { double("Stages::ReviewHandoff", enable_auto_merge!: nil, notify_reviewers!: nil) }

  def actions(stage) = stage.stage_runs.reorder(:id).pluck(:action)

  describe Stages::SimpleImplementationFinish do
    let(:stage) { workflow.stages.find_by!(stage_type: :simple_implementation) }

    it "moves on to the check without looking for a PR" do
      described_class.new(workflow: workflow, stage: stage).call("out")

      expect(workflow.reload).to have_attributes(status: "ci_checking", processing: false, ai_pid: nil, github_pr_url: nil)
      expect(actions(stage)).to eq %w[ran_implementation]
    end
  end

  describe Stages::CiCheckFinish do
    let(:stage) { workflow.stages.find_by!(stage_type: :ci_check) }

    it "keeps the log path and exit status, and hands over to the verify stage even when the check failed" do
      log = Tempfile.new("ci").tap { |f| f.write("boom\n"); f.flush }
      workflow.update!(ai_log_path: log.path, status: :ci_checking)

      described_class.new(workflow: workflow, stage: stage).call(1)

      expect(workflow.reload).to have_attributes(status: "ci_verifying", ci_output_path: log.path, ci_exit_status: 1, processing: false, ai_pid: nil)
      expect(stage.stage_runs.last.output).to include("exit status 1", "boom")
      expect(actions(stage)).to eq %w[ci_check_completed]
    end
  end

  describe Stages::CiVerifyFinish do
    let(:stage) { workflow.stages.find_by!(stage_type: :ci_verify) }
    let(:check_stage) { workflow.stages.find_by!(stage_type: :ci_check) }

    def finish(output) = described_class.new(workflow: workflow, stage: stage, project: project).call(output)

    it "fails the stage visibly without a verdict line" do
      expect { finish("no verdict") }.to raise_error(AiCli::CommandError, /CI_VERDICT/)
    end

    it "goes back to the check on FAILED" do
      check_stage.log_run!("ci_check_completed")

      finish("fixed some\nCI_VERDICT: FAILED")

      expect(workflow.reload).to have_attributes(status: "ci_checking", processing: false)
      expect(actions(stage)).to eq %w[ci_verify_failed]
    end

    it "parks the workflow as errored once the rounds are used up" do
      2.times { check_stage.log_run!("ci_check_completed") }

      finish("CI_VERDICT: FAILED")

      expect(workflow.reload.status).to eq "errored"
      expect(actions(stage)).to eq %w[ci_verify_failed ci_rounds_exhausted]
    end

    it "opens the PR stage on PASSED" do
      finish("CI_VERDICT: PASSED")

      expect(workflow.reload.status).to eq "opening_pr"
      expect(actions(stage)).to eq %w[ci_verify_passed]
    end
  end

  describe Stages::PrOpenedFinish do
    let(:stage) { workflow.stages.find_by!(stage_type: :pr_create) }

    it "records the PR, starts review and logs pr_created" do
      described_class.new(workflow: workflow, stage: stage, project: project, github: github, handoff: handoff).call("out", action: "pr_created")

      expect(workflow.reload).to have_attributes(status: "reviewing", github_pr_url: "https://github.com/acme/widgets/pull/9")
      expect(actions(stage)).to eq %w[pr_created]
    end
  end
end
