require "rails_helper"

RSpec.describe AgentRuns::StateRoot do
  describe ".join" do
    it "builds under the configured root" do
      expect(described_class.join("brainstorms", "1")).to eq(
        Pathname(Rails.configuration.x.state_root).join("brainstorms", "1")
      )
    end

    it "uses tmp/test_state in the test environment, not tmp" do
      expect(Rails.configuration.x.state_root).to eq(Rails.root.join("tmp", "test_state"))
      expect(described_class.join("brainstorms")).to eq(Rails.root.join("tmp", "test_state", "brainstorms"))
      expect(described_class.join("brainstorms")).not_to eq(Rails.root.join("tmp", "brainstorms"))
    end
  end

  it "keeps every on-disk state ROOT under the configured StateRoot" do
    base = described_class.join.to_s
    {
      Workflows::ImageStore::DEFAULT_ROOT => "workflow_images",
      Brainstorm::Planner::ROOT => "brainstorms",
      Jira::AgentFetcher::ROOT => "jira_sync",
      Bugsnag::Triager::ROOT => "bugsnag_syncs",
      Slack::MentionFetcher::ROOT => "slack_reviews",
      Slack::PingRun::ROOT => "slack_pings"
    }.each do |root, subdir|
      expect(root.to_s).to start_with(base)
      expect(root).to eq(described_class.join(subdir))
    end
  end
end
