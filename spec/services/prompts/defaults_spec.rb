require "rails_helper"

RSpec.describe Prompts::Defaults do
  {
    "pr_review" => nil,
    "jira_update" => "JIRA_RESULT",
    "uat_test" => "UAT_RESULT",
    "local_test" => "LOCAL_TEST_RESULT"
  }.each do |type, marker|
    describe ".for(#{type.inspect})" do
      it "returns a non-empty body" do
        expect(described_class.for(type)).to be_present
      end

      it "tells the agent to print #{marker}" do
        expect(described_class.for(type)).to include("`#{marker}:") if marker
      end
    end
  end

  %w[implementation pr_check task runbook_step].each do |type|
    it "returns nil for #{type}" do
      expect(described_class.for(type)).to be_nil
    end
  end

  it "is frozen" do
    expect(described_class::BODIES).to be_frozen
  end
end
