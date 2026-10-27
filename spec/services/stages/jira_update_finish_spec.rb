require "rails_helper"

RSpec.describe Stages::JiraUpdateFinish, type: :service do
  let_tmpdir(:local_directory, "jira-update-finish-spec")
  let(:project_attributes) { {} }
  let(:project) { build_jira_project(**{ local_directory: local_directory }.merge(project_attributes)) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "JLF-1", branch_name: "jira-lifecycle", status: :implementing, **running_ai_run)
  end
  let(:stage) { build_stage(workflow, :jira_update) }
  let(:now) { Time.zone.local(2026, 10, 20, 12, 0) }
  let(:clock) { -> { now } }

  def finish(output)
    described_class.new(workflow: workflow, stage: stage, project: project, clock: clock).call(output)
  end

  def expect_ai_run_reset
    expect(workflow.reload).to have_finished_ai_run
  end

  let(:uat_attributes) { { uat_test_enabled: true, uat_url: "https://uat.example.com", uat_test_delay_minutes: 30 } }

  it "raises without a JIRA_RESULT line and leaves the workflow untouched" do
    expect { finish("agent output") }
      .to raise_error(AiCli::CommandError, "agent finished without a JIRA_RESULT line, treating the Jira update as failed")

    expect(workflow.reload).to have_attributes(status: "implementing", processing: true)
    expect(stage_actions(stage)).to be_empty
  end

  context "when the project has UAT testing ready" do
    let(:project_attributes) { uat_attributes }

    it "schedules the UAT test for a UAT outcome" do
      run_at = now + 30.minutes
      finish("JIRA_RESULT: UAT")

      expect(workflow.reload).to have_attributes(status: "uat_waiting", uat_test_at: run_at)
      expect_ai_run_reset
      expect(stage_actions(stage)).to eq(%w[jira_updated uat_test_scheduled])
      expect(stage.stage_runs.find_by(action: "uat_test_scheduled").output)
        .to eq "UAT test scheduled for #{run_at.iso8601}"
    end

    it "matches the UAT outcome case-insensitively" do
      finish("JIRA_RESULT: uat")

      expect(workflow.reload.status).to eq "uat_waiting"
    end

    it "does not schedule a UAT test for a RELEASEABLE outcome" do
      finish("JIRA_RESULT: RELEASEABLE")

      expect(workflow.reload).to have_attributes(status: "jira_updated", uat_test_at: nil)
      expect(stage_actions(stage)).to eq(%w[jira_updated])
    end
  end

  context "when the project has no UAT testing" do
    it "marks the workflow jira_updated even for a UAT outcome" do
      finish("JIRA_RESULT: UAT")

      expect(workflow.reload).to have_attributes(status: "jira_updated", uat_test_at: nil)
      expect_ai_run_reset
      expect(stage_actions(stage)).to eq(%w[jira_updated])
    end
  end
end
