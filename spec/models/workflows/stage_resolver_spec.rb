require "rails_helper"

RSpec.describe Workflows::StageResolver do
  statuses = Workflow.statuses.keys

  {
    "development/jira" => [ { kind: "development", personal: false },
                            { "implementing" => "implementation", "reviewing" => "pr_check", "merged" => "jira_update",
                              "uat_testing" => "uat_test", "local_testing" => "local_test", "ci_checking" => "ci_check",
                              "ci_verifying" => "ci_verify", "opening_pr" => "pr_create" } ],
    "development/personal" => [ { kind: "development", personal: true }, { "implementing" => "task" } ],
    "pr_review" => [ { kind: "pr_review", personal: false }, { "implementing" => "pr_review" } ]
  }.each do |label, (args, expected)|
    describe label do
      statuses.each do |status|
        it "maps #{status} to #{expected[status].inspect}" do
          expect(described_class.stage_type_for(status: status, **args)).to eq(expected[status])
        end
      end
    end
  end

  it "prefers the pr_review map over the personal one" do
    expect(described_class.stage_type_for(status: "implementing", kind: "pr_review", personal: true)).to eq("pr_review")
  end

  it "accepts symbols" do
    expect(described_class.stage_type_for(status: :reviewing, kind: :development, personal: false)).to eq("pr_check")
  end

  it "lists the lazily created stage types" do
    expect(described_class::LAZY_STAGE_TYPES).to contain_exactly("jira_update", "uat_test", "local_test", "ci_check", "ci_verify", "pr_create", "simple_implementation")
  end
end
