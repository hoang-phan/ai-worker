require "rails_helper"

RSpec.describe Stages::UatTestFinish, type: :service do
  let_jira_project("uat-test-finish-spec")
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "JLF-1", branch_name: "jira-lifecycle", status: :implementing, **running_ai_run)
  end
  let(:stage) { workflow.stages.create!(stage_type: :uat_test, name: "uat_test") }

  def finish(output)
    described_class.new(workflow: workflow, stage: stage).call(output)
  end

  def expect_ai_run_reset
    expect(workflow.reload).to have_finished_ai_run
  end

  %w[PASSED FAILED BLOCKED].each do |verdict|
    it "completes on UAT_RESULT: #{verdict}" do
      finish("UAT_RESULT: #{verdict}")

      expect(workflow.reload.status).to eq "uat_tested"
      expect_ai_run_reset
      expect(stage_actions(stage)).to eq(%w[uat_test_completed])
    end
  end

  it "raises without a UAT_RESULT line and leaves the workflow untouched" do
    expect { finish("agent output") }
      .to raise_error(AiCli::CommandError, "agent finished without a UAT_RESULT line, treating the UAT test as failed")

    expect(workflow.reload).to have_attributes(status: "implementing", processing: true)
    expect(stage_actions(stage)).to be_empty
  end
end
