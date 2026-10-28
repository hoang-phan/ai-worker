require "rails_helper"

RSpec.describe Prompts::StageSectionList do
  subject(:section_list) do
    described_class.new(workflow: workflow, stage: stage, latest_log: latest_log)
  end

  # Raises if called so examples that must not look up a log fail loudly when wiring regresses.
  let(:latest_log_calls) { [] }
  let(:latest_log) do
    ->(workflow_id) do
      latest_log_calls << workflow_id
      raise "latest_log should not be called"
    end
  end

  let_tmpdir(:local_directory, "stage-section-list-spec")
  # Jira project so local_test_ready? can be true via real attrs (needs jira? + local_test_enabled + local_url).
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:workflow) { build_jira_workflow(project, kind: :development) }
  let(:stage) { workflow.stages.create!(stage_type: :task) }

  describe "#sections" do
    it "includes retry text with the previous log for a failed implementation run" do
      stage.update!(stage_type: :implementation, prompt: "Implement")
      stage.stage_runs.create!(action: "failed")
      previous_log = "/tmp/runs/workflow-#{workflow.id}.log"
      latest_log = ->(id) {
        latest_log_calls << id
        previous_log
      }

      text = described_class.new(workflow: workflow, stage: stage, latest_log: latest_log).to_s

      expect(latest_log_calls).to eq([ workflow.id ])
      expect(text).to include("A previous attempt at this stage ended without finishing", previous_log)
    end

    it "does not look up a retry log unless a simple implementation's last action failed" do
      stage.update!(stage_type: :simple_implementation, prompt: "Implement")
      stage.stage_runs.create!(action: "started")

      expect(section_list.to_s).not_to include("A previous attempt at this stage ended without finishing")
      expect(latest_log_calls).to be_empty
    end

    it "does not look up a retry log for failed non-implementation stages" do
      stage.update!(prompt: "Do it")
      stage.stage_runs.create!(action: "failed")

      expect(section_list.to_s).not_to include("A previous attempt at this stage ended without finishing")
      expect(latest_log_calls).to be_empty
    end

    it "includes this workflow's local-test feedback for a pr_check on a ready project" do
      stage.update!(stage_type: :pr_check, prompt: "Fix")
      project.update!(local_test_enabled: true, local_url: "http://localhost:3000")
      workflow.update!(local_test_feedback: "Login button is broken")

      expect(section_list.to_s).to include(
        "<local_test_feedback>",
        "Login button is broken",
        "LOCAL_RETEST:"
      )
    end

    it "does not include local-test feedback outside pr_check even when the project is ready" do
      stage.update!(prompt: "Do it")
      project.update!(local_test_enabled: true, local_url: "http://localhost:3000")
      workflow.update!(local_test_feedback: "Login button is broken")

      expect(section_list.to_s).not_to include("Login button is broken", "LOCAL_RETEST:", "<local_test_feedback>")
    end

    it "includes a fixed summary for pr_check when the Slack notifier is enabled" do
      stage.update!(stage_type: :pr_check, prompt: "Fix")
      project.update!(slack_review_channel: "C0B5XFY2F0T")

      expect(section_list.to_s).to include("FIXED_SUMMARY_BEGIN", "FIXED_SUMMARY_END")
    end

    it "does not include a fixed summary outside pr_check even when the notifier is enabled" do
      stage.update!(prompt: "Do it")
      project.update!(slack_review_channel: "C0B5XFY2F0T")

      expect(section_list.to_s).not_to include("FIXED_SUMMARY_BEGIN")
    end

    it "includes project agent lessons in the output" do
      stage.update!(prompt: "Do it")
      project.update!(agent_lessons: "Use the shared error_summary partial on forms")

      expect(section_list.to_s).to include(
        "Lessons from earlier reviews of this project",
        "Use the shared error_summary partial on forms"
      )
    end

    it "returns the sections in order" do
      stage.update!(prompt: "Do it")

      expect(section_list.sections.map(&:class)).to eq(
        [
          Prompts::StageSections::Retry, Prompts::StageSections::LocalFeedback,
          Prompts::StageSections::FixedSummary, Prompts::StageSections::LessonsRequest,
          Prompts::StageSections::FollowUps, Prompts::StageSections::Lessons,
          Prompts::StageSections::CheckOutput
        ]
      )
    end
  end

  describe "#to_s" do
    it "joins the section texts in order" do
      outputs = described_class.new(workflow: workflow, stage: stage, latest_log: latest_log)
                               .sections.map(&:to_s)

      expect(section_list.to_s).to eq(outputs.join)
    end
  end

  describe "defaults" do
    it "builds a Slack::ReviewNotifier for the project lazily, only for pr_check" do
      stage.update!(stage_type: :pr_check)
      project.update!(slack_review_channel: "C0B5XFY2F0T")

      # Real notifier: enabled? is channel presence only (no network). Omit notifier: to exercise the default.
      expect(described_class.new(workflow: workflow, stage: stage, latest_log: latest_log).to_s)
        .to include("FIXED_SUMMARY_BEGIN")
    end

    it "looks up the previous log through AiCli::RunLogs.latest" do
      stage.update!(stage_type: :implementation, prompt: "Implement")
      stage.stage_runs.create!(action: "failed")
      # StageSectionList's default calls RunLogs.latest(id) without dir:; write under DIR rather than
      # adding a production seam to forward a tmp dir.
      FileUtils.mkdir_p(AiCli::RunLogs::DIR)
      log_path = AiCli::RunLogs.new_path(workflow.id, at: Time.current)
      File.write(log_path, "previous attempt")

      begin
        text = described_class.new(workflow: workflow, stage: stage).to_s

        expect(text).to include("A previous attempt at this stage ended without finishing", log_path)
      ensure
        FileUtils.rm_f(log_path)
      end
    end
  end
end
