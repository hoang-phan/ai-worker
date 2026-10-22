require "rails_helper"

RSpec.describe Stages::JiraLifecycleFinish, type: :service do
  let(:local_directory) { Dir.mktmpdir("jira-lifecycle-finish-spec") }
  let(:project_attributes) { {} }
  let(:project) { build_jira_project(**{ local_directory: local_directory }.merge(project_attributes)) }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "JLF-1", branch_name: "jira-lifecycle", status: :implementing, processing: true, ai_pid: 123,
                                 ai_log_path: "/tmp/x.log", ai_started_at: Time.current, ai_log_offset: 42)
  end
  let(:stage_type) { :jira_update }
  let(:stage) { workflow.stages.create!(stage_type: stage_type, name: stage_type.to_s) }

  def finish(output)
    described_class.new(workflow: workflow, stage: stage, project: project).call(output)
  end

  def actions = stage.stage_runs.reorder(:id).pluck(:action)

  def expect_ai_run_reset
    expect(workflow.reload).to have_attributes(processing: false, ai_pid: nil, ai_log_path: nil,
                                                ai_started_at: nil, ai_log_offset: 0)
  end

  after do
    FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory)
  end

  describe "jira_update" do
    let(:uat_attributes) { { uat_test_enabled: true, uat_url: "https://uat.example.com", uat_test_delay_minutes: 30 } }

    it "raises without a JIRA_RESULT line and leaves the workflow untouched" do
      expect { finish("agent output") }
        .to raise_error(AiCli::CommandError, "agent finished without a JIRA_RESULT line, treating the Jira update as failed")

      expect(workflow.reload).to have_attributes(status: "implementing", processing: true)
      expect(actions).to be_empty
    end

    context "when the project has UAT testing ready" do
      let(:project_attributes) { uat_attributes }

      it "schedules the UAT test for a UAT outcome" do
        freeze_time do
          finish("JIRA_RESULT: UAT")

          expect(workflow.reload).to have_attributes(status: "uat_waiting", uat_test_at: 30.minutes.from_now)
          expect_ai_run_reset
          expect(actions).to eq(%w[jira_updated uat_test_scheduled])
          expect(stage.stage_runs.find_by(action: "uat_test_scheduled").output)
            .to eq "UAT test scheduled for #{30.minutes.from_now.iso8601}"
        end
      end

      it "matches the UAT outcome case-insensitively" do
        finish("JIRA_RESULT: uat")

        expect(workflow.reload.status).to eq "uat_waiting"
      end

      it "does not schedule a UAT test for a RELEASEABLE outcome" do
        finish("JIRA_RESULT: RELEASEABLE")

        expect(workflow.reload).to have_attributes(status: "jira_updated", uat_test_at: nil)
        expect(actions).to eq(%w[jira_updated])
      end
    end

    context "when the project has no UAT testing" do
      it "marks the workflow jira_updated even for a UAT outcome" do
        finish("JIRA_RESULT: UAT")

        expect(workflow.reload).to have_attributes(status: "jira_updated", uat_test_at: nil)
        expect_ai_run_reset
        expect(actions).to eq(%w[jira_updated])
      end
    end
  end

  describe "uat_test" do
    let(:stage_type) { :uat_test }

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
end
