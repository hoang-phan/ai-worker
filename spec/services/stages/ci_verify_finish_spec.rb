require "rails_helper"

RSpec.describe Stages::CiVerifyFinish, type: :service do
  let(:project) { build_ci_project(ci_max_rounds: 2) }
  let(:workflow) do
    build_ci_workflow(project, status: :ci_verifying, processing: true, ai_pid: 1, ai_log_path: "/tmp/x.log", ai_started_at: Time.current, ai_log_offset: 7)
  end
  let(:stage) { workflow.stages.find_by!(stage_type: :ci_verify) }
  let(:check_stage) { workflow.stages.find_by!(stage_type: :ci_check) }

  def actions(stage) = stage.stage_runs.reorder(:id).pluck(:action)

  def finish(output) = described_class.new(workflow: workflow, stage: stage, project: project).call(output)

  it "fails the stage visibly without a verdict line" do
    expect { finish("no verdict") }.to raise_error(AiCli::CommandError, /CI_VERDICT/)
  end

  it "goes back to the check on FAILED" do
    check_stage.log_run!("ci_check_completed")

    finish("fixed some\nCI_VERDICT: FAILED")

    expect(workflow.reload).to have_attributes(Workflow::AI_RUN_RESET.merge(status: "ci_checking"))
    expect(actions(stage)).to eq %w[ci_verify_failed]
  end

  it "goes back to the check when completed rounds are one below ci_max_rounds" do
    check_stage.log_run!("ci_check_completed") # 1 of 2

    finish("CI_VERDICT: FAILED")

    expect(workflow.reload.status).to eq "ci_checking"
    expect(actions(stage)).to eq %w[ci_verify_failed]
    expect(actions(stage)).not_to include("ci_rounds_exhausted")
  end

  it "parks the workflow as errored once the rounds are used up" do
    2.times { check_stage.log_run!("ci_check_completed") }

    finish("CI_VERDICT: FAILED")

    expect(workflow.reload).to have_attributes(Workflow::AI_RUN_RESET.merge(status: "errored"))
    expect(actions(stage)).to eq %w[ci_verify_failed ci_rounds_exhausted]
  end

  it "opens the PR stage on PASSED" do
    finish("CI_VERDICT: PASSED")

    expect(workflow.reload).to have_attributes(Workflow::AI_RUN_RESET.merge(status: "opening_pr"))
    expect(actions(stage)).to eq %w[ci_verify_passed]
  end

  it "uses the last verdict line when the log echoes the prompt's example first" do
    finish("CI_VERDICT: PASSED|FAILED example\nCI_VERDICT: FAILED\nmore\nCI_VERDICT: PASSED")

    expect(workflow.reload.status).to eq "opening_pr"
    expect(actions(stage)).to eq %w[ci_verify_passed]
  end

  it "uses the last verdict line when a later one is FAILED" do
    finish("CI_VERDICT: PASSED\nCI_VERDICT: FAILED")

    expect(workflow.reload.status).to eq "ci_checking"
    expect(actions(stage)).to eq %w[ci_verify_failed]
  end
end
