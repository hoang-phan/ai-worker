require "rails_helper"

RSpec.describe Stages::CiVerifyFinish, type: :service do
  let(:project) { build_ci_project(ci_max_rounds: 2) }
  let(:workflow) do
    build_ci_workflow(project, status: :ci_verifying, **running_ai_run)
  end
  let(:stage) { workflow.stages.find_by!(stage_type: :ci_verify) }
  let(:check_stage) { workflow.stages.find_by!(stage_type: :ci_check) }

  let(:handoff) { double("Stages::ReviewHandoff", notify_reviewers!: nil) }

  def finish(output) = described_class.new(workflow: workflow, stage: stage, project: project, handoff: handoff).call(output)

  it "fails the stage visibly without a verdict line" do
    expect { finish("no verdict") }.to raise_error(AiCli::CommandError, /CI_VERDICT/)
  end

  it "goes back to the check on FAILED" do
    check_stage.log_run!("ci_check_completed")

    finish("fixed some\nCI_VERDICT: FAILED")

    expect(workflow.reload).to have_attributes(status: "ci_checking").and have_finished_ai_run
    expect(stage_actions(stage)).to eq %w[ci_verify_failed]
  end

  it "goes back to the check when completed rounds are one below ci_max_rounds" do
    check_stage.log_run!("ci_check_completed") # 1 of 2

    finish("CI_VERDICT: FAILED")

    expect(workflow.reload.status).to eq "ci_checking"
    expect(stage_actions(stage)).to eq %w[ci_verify_failed]
    expect(stage_actions(stage)).not_to include("ci_rounds_exhausted")
  end

  it "parks the workflow as errored once the rounds are used up" do
    2.times { check_stage.log_run!("ci_check_completed") }

    finish("CI_VERDICT: FAILED")

    expect(workflow.reload).to have_attributes(status: "errored").and have_finished_ai_run
    expect(stage_actions(stage)).to eq %w[ci_verify_failed ci_rounds_exhausted]
  end

  it "goes on to review and pings the reviewers on PASSED (the PR is already open)" do
    finish("CI_VERDICT: PASSED")

    expect(workflow.reload).to have_attributes(status: "reviewing").and have_finished_ai_run
    expect(stage_actions(stage)).to eq %w[ci_verify_passed]
    expect(handoff).to have_received(:notify_reviewers!)
  end

  it "goes on to local testing without pinging reviewers on PASSED when the project is local-test ready" do
    project.update!(local_test_enabled: true, local_url: "http://localhost:3000")

    finish("CI_VERDICT: PASSED")

    expect(workflow.reload.status).to eq "local_testing"
    expect(handoff).not_to have_received(:notify_reviewers!)
  end

  it "uses the last verdict line when the log echoes the prompt's example first" do
    finish("CI_VERDICT: PASSED|FAILED example\nCI_VERDICT: FAILED\nmore\nCI_VERDICT: PASSED")

    expect(workflow.reload.status).to eq "reviewing"
    expect(stage_actions(stage)).to eq %w[ci_verify_passed]
  end

  it "uses the last verdict line when a later one is FAILED" do
    finish("CI_VERDICT: PASSED\nCI_VERDICT: FAILED")

    expect(workflow.reload.status).to eq "ci_checking"
    expect(stage_actions(stage)).to eq %w[ci_verify_failed]
  end
end
