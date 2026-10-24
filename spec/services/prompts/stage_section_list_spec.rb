require "rails_helper"

RSpec.describe Prompts::StageSectionList do
  subject(:section_list) do
    described_class.new(workflow: workflow, stage: stage, notifier: notifier, latest_log: latest_log)
  end

  let(:notifier) { instance_double(Slack::ReviewNotifier, enabled?: false) }
  let(:latest_log) { ->(_workflow_id) { nil } }

  let_tmpdir(:local_directory, "stage-section-list-spec")
  let(:project) { build_personal_project(local_directory: local_directory, kind: :personal) }
  let(:workflow) do
    build_task_workflow(project, kind: :development, task_description: "Do the thing")
  end
  let(:stage_type) { :task }
  let(:stage) { workflow.stages.create!(stage_type: stage_type) }

  describe "#sections" do
    it "passes retry a log only for a failed implementation run from this workflow" do
      stage.update!(stage_type: :implementation, prompt: "Implement")
      stage.stage_runs.create!(action: "failed")
      previous_log = "/tmp/runs/workflow-#{workflow.id}.log"
      latest_log = instance_double(Proc)
      retry_section = instance_double(Prompts::StageSections::Retry, to_s: "")

      expect(latest_log).to receive(:call).with(workflow.id).and_return(previous_log)
      expect(Prompts::StageSections::Retry).to receive(:new).with(
        stage_type: "implementation", last_action: "failed", previous_log: previous_log
      ).and_return(retry_section)

      described_class.new(workflow: workflow, stage: stage, notifier: notifier, latest_log: latest_log).sections
    end

    it "does not look up a retry log unless a simple implementation's last action failed" do
      stage.update!(stage_type: :simple_implementation, prompt: "Implement")
      stage.stage_runs.create!(action: "started")
      retry_section = instance_double(Prompts::StageSections::Retry, to_s: "")

      expect(latest_log).not_to receive(:call)
      expect(Prompts::StageSections::Retry).to receive(:new).with(
        stage_type: "simple_implementation", last_action: "started", previous_log: nil
      ).and_return(retry_section)

      section_list.sections
    end

    it "does not look up a retry log for failed non-implementation stages" do
      stage.update!(prompt: "Do it")
      stage.stage_runs.create!(action: "failed")
      retry_section = instance_double(Prompts::StageSections::Retry, to_s: "")

      expect(latest_log).not_to receive(:call)
      expect(Prompts::StageSections::Retry).to receive(:new).with(
        stage_type: "task", last_action: "failed", previous_log: nil
      ).and_return(retry_section)

      section_list.sections
    end

    it "passes local-test readiness and this workflow's feedback to local feedback" do
      stage.update!(stage_type: :pr_check, prompt: "Fix")
      allow(project).to receive(:local_test_ready?).and_return(true)
      allow(workflow).to receive(:local_test_feedback).and_return("Login button is broken")
      local_feedback = instance_double(Prompts::StageSections::LocalFeedback, to_s: "")

      expect(Prompts::StageSections::LocalFeedback).to receive(:new).with(
        stage_type: "pr_check", local_test_ready: true, feedback: "Login button is broken"
      ).and_return(local_feedback)

      section_list.sections
    end

    it "does not mark a non-pr-check stage as local-test ready" do
      stage.update!(prompt: "Do it")
      allow(project).to receive(:local_test_ready?).and_return(true)
      local_feedback = instance_double(Prompts::StageSections::LocalFeedback, to_s: "")

      expect(Prompts::StageSections::LocalFeedback).to receive(:new).with(
        stage_type: "task", local_test_ready: false, feedback: workflow.local_test_feedback
      ).and_return(local_feedback)

      section_list.sections
    end

    it "only enables fixed summaries for pr checks when the notifier is enabled" do
      stage.update!(stage_type: :pr_check, prompt: "Fix")
      allow(notifier).to receive(:enabled?).and_return(true)
      fixed_summary = instance_double(Prompts::StageSections::FixedSummary, to_s: "")

      expect(Prompts::StageSections::FixedSummary).to receive(:new).with(
        stage_type: "pr_check", notify_enabled: true
      ).and_return(fixed_summary)

      section_list.sections
    end

    it "does not enable fixed summaries outside pr checks" do
      stage.update!(prompt: "Do it")
      allow(notifier).to receive(:enabled?).and_return(true)
      fixed_summary = instance_double(Prompts::StageSections::FixedSummary, to_s: "")

      expect(Prompts::StageSections::FixedSummary).to receive(:new).with(
        stage_type: "task", notify_enabled: false
      ).and_return(fixed_summary)

      section_list.sections
    end

    it "passes project lessons to the lessons section" do
      stage.update!(prompt: "Do it")
      project.update!(agent_lessons: "Use the shared error_summary partial on forms")
      lessons = instance_double(Prompts::StageSections::Lessons, to_s: "")

      expect(Prompts::StageSections::Lessons).to receive(:new).with(
        stage_type: "task", lessons: "Use the shared error_summary partial on forms"
      ).and_return(lessons)

      section_list.sections
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
      outputs = described_class.new(workflow: workflow, stage: stage, notifier: notifier, latest_log: latest_log)
                               .sections.map(&:to_s)

      expect(section_list.to_s).to eq(outputs.join)
    end
  end

  describe "defaults" do
    it "builds a Slack::ReviewNotifier for the project lazily, only for pr_check" do
      stage.update!(stage_type: :pr_check)
      default_notifier = instance_double(Slack::ReviewNotifier, enabled?: true)
      allow(Slack::ReviewNotifier).to receive(:new).with(project).and_return(default_notifier)
      fixed_summary = instance_double(Prompts::StageSections::FixedSummary, to_s: "")

      expect(Prompts::StageSections::FixedSummary).to receive(:new).with(
        stage_type: "pr_check", notify_enabled: true
      ).and_return(fixed_summary)

      described_class.new(workflow: workflow, stage: stage).sections
    end

    it "looks up the previous log through AiCli::RunLogs.latest" do
      stage.update!(stage_type: :implementation)
      stage.stage_runs.create!(action: "failed")
      allow(AiCli::RunLogs).to receive(:latest).with(workflow.id).and_return("/tmp/runs/x.log")
      retry_section = instance_double(Prompts::StageSections::Retry, to_s: "")

      expect(Prompts::StageSections::Retry).to receive(:new).with(
        stage_type: "implementation", last_action: "failed", previous_log: "/tmp/runs/x.log"
      ).and_return(retry_section)

      described_class.new(workflow: workflow, stage: stage, notifier: notifier).sections
    end
  end
end
