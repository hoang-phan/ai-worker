require "rails_helper"

RSpec.describe Stages::LocalTestFinish, type: :service do
  let_tmpdir(:local_directory, "local-test-finish-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "DONE-1", branch_name: "local-test-finish", github_pr_url: "https://github.com/acme/widgets/pull/1", status: :local_testing, **running_ai_run)
  end
  let(:stage) { workflow.stages.create!(stage_type: :local_test, name: "local_test") }
  let(:handoff) { double("Stages::ReviewHandoff", enable_auto_merge!: nil, notify_reviewers!: nil) }

  def finish(output)
    described_class.new(workflow: workflow, stage: stage, handoff: handoff).call(output)
  end

  it "moves to reviewing, enables auto-merge on PASSED and notifies reviewers" do
    finish("LOCAL_TEST_RESULT: PASSED")

    expect(workflow.reload).to have_attributes(status: "reviewing", local_test_feedback: nil).and have_finished_ai_run
    expect(stage_actions(stage)).to eq(%w[local_test_completed])
    expect(handoff).to have_received(:enable_auto_merge!).with(workflow.github_pr_url)
    expect(handoff).to have_received(:notify_reviewers!).with(no_args)
  end

  it "stores feedback for a FAILED result while rounds remain" do
    finish("LOCAL_TEST_FEEDBACK_BEGIN\nThe login button is broken\nLOCAL_TEST_FEEDBACK_END\nLOCAL_TEST_RESULT: FAILED")

    expect(workflow.reload).to have_attributes(status: "reviewing", local_test_feedback: "The login button is broken")
    expect(stage_actions(stage)).to eq(%w[local_test_completed])
    expect(handoff).not_to have_received(:enable_auto_merge!)
    expect(handoff).to have_received(:notify_reviewers!).with(no_args)
  end

  it "logs exhausted rounds and leaves no feedback when FAILED after the final round" do
    2.times { stage.log_run!("local_test_completed") }

    finish("LOCAL_TEST_FEEDBACK_BEGIN\nThe login button is broken\nLOCAL_TEST_FEEDBACK_END\nLOCAL_TEST_RESULT: FAILED")

    expect(workflow.reload).to have_attributes(status: "reviewing", local_test_feedback: nil)
    expect(stage_actions(stage)).to eq(%w[local_test_completed local_test_completed local_test_completed local_test_rounds_exhausted])
    expect(handoff).not_to have_received(:enable_auto_merge!)
    expect(handoff).to have_received(:notify_reviewers!).with(no_args)
  end

  it "raises without a LOCAL_TEST_RESULT line" do
    expect { finish("agent output") }
      .to raise_error(AiCli::CommandError, "agent finished without a LOCAL_TEST_RESULT line, treating the local test as failed")
  end
end
