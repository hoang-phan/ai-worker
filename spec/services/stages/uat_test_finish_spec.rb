require "rails_helper"

RSpec.describe Stages::UatTestFinish, type: :service do
  let_tmpdir(:local_directory, "uat-test-finish-spec")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "JLF-1", branch_name: "jira-lifecycle", status: :implementing, processing: true, ai_pid: 123,
                                 ai_log_path: "/tmp/x.log", ai_started_at: Time.current, ai_log_offset: 42)
  end
  let(:stage) { workflow.stages.create!(stage_type: :uat_test, name: "uat_test") }

  def finish(output)
    described_class.new(workflow: workflow, stage: stage).call(output)
  end

  def actions = stage.stage_runs.reorder(:id).pluck(:action)

  def expect_ai_run_reset
    expect(workflow.reload).to have_attributes(processing: false, ai_pid: nil, ai_log_path: nil,
                                                ai_started_at: nil, ai_log_offset: 0)
  end

  %w[PASSED FAILED BLOCKED].each do |verdict|
    it "completes on UAT_RESULT: #{verdict}" do
      finish("UAT_RESULT: #{verdict}")

      expect(workflow.reload.status).to eq "uat_tested"
      expect_ai_run_reset
      expect(actions).to eq(%w[uat_test_completed])
    end
  end

  it "raises without a UAT_RESULT line and leaves the workflow untouched" do
    expect { finish("agent output") }
      .to raise_error(AiCli::CommandError, "agent finished without a UAT_RESULT line, treating the UAT test as failed")

    expect(workflow.reload).to have_attributes(status: "implementing", processing: true)
    expect(actions).to be_empty
  end
end
