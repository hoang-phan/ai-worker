require "rails_helper"

RSpec.describe Prompts::StageSections do
  describe Prompts::StageSections::Retry do
    def section(stage_type: "implementation", last_action: "failed", previous_log: "/tmp/run.log")
      described_class.new(stage_type: stage_type, last_action: last_action, previous_log: previous_log).to_s
    end

    it "points at the previous log after a failed implementation run" do
      expect(section).to include("A previous attempt at this stage ended without finishing", "/tmp/run.log")
    end

    it "is empty unless the stage is an implementation" do
      expect(section(stage_type: "pr_check")).to eq("")
    end

    it "is empty unless the last run failed" do
      expect(section(last_action: "completed")).to eq("")
    end

    it "is empty without a previous log" do
      expect(section(previous_log: nil)).to eq("")
    end
  end

  describe Prompts::StageSections::LocalFeedback do
    def section(stage_type: "pr_check", local_test_ready: true, feedback: nil)
      described_class.new(stage_type: stage_type, local_test_ready: local_test_ready, feedback: feedback).to_s
    end

    it "only asks the retest question when there is no feedback" do
      expect(section).to start_with("\nThis project is also tested locally").and include("LOCAL_RETEST: YES")
    end

    it "includes the findings as data when there is feedback" do
      expect(section(feedback: "button broken")).to include("<local_test_feedback>\nbutton broken\n</local_test_feedback>", "LOCAL_RETEST: NO")
    end

    it "treats blank feedback as none" do
      expect(section(feedback: " ")).not_to include("local_test_feedback")
    end

    it "is empty for other stage types" do
      expect(section(stage_type: "implementation")).to eq("")
    end

    it "is empty when the project is not ready for local tests" do
      expect(section(local_test_ready: false)).to eq("")
    end
  end

  describe Prompts::StageSections::FixedSummary do
    def section(stage_type: "pr_check", notify_enabled: true)
      described_class.new(stage_type: stage_type, notify_enabled: notify_enabled).to_s
    end

    it "asks for a fixed summary on a pr_check run with notifications" do
      expect(section).to include("FIXED_SUMMARY_BEGIN", "FIXED_SUMMARY_END")
    end

    it "is empty for other stage types" do
      expect(section(stage_type: "implementation")).to eq("")
    end

    it "is empty when notifications are disabled" do
      expect(section(notify_enabled: false)).to eq("")
    end
  end

  describe Prompts::StageSections::CheckOutput do
    it "applies to implementation and pr_check stages" do
      %w[implementation pr_check].each do |type|
        expect(described_class.new(stage_type: type).to_s).to include("Running checks (CI, linters, test suites)")
      end
    end

    it "accepts symbols" do
      expect(described_class.new(stage_type: :pr_check).to_s).not_to be_empty
    end

    it "is empty for other stage types" do
      expect(described_class.new(stage_type: "task").to_s).to eq("")
    end
  end
end
