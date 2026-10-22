require "rails_helper"

RSpec.describe Prompts::ProjectPlaceholders do
  let(:project) do
    Project.new(
      jira_tester: "tess", uat_url: "https://uat.example", test_instructions: "run tests", uat_instructions: "check uat",
      local_url: "http://localhost:3000", local_instructions: "boot it", ci_instructions: "watch ci",
      ci_verify_instructions: "verify ci", pr_instructions: "open pr", ci_command: "bin/ci"
    )
  end

  it "maps each project field to its token" do
    expect(described_class.for(project)).to eq(
      "{TESTER}" => "tess",
      "{UAT_URL}" => "https://uat.example",
      "{TEST_INSTRUCTIONS}" => "run tests",
      "{UAT_INSTRUCTIONS}" => "check uat",
      "{LOCAL_URL}" => "http://localhost:3000",
      "{LOCAL_INSTRUCTIONS}" => "boot it",
      "{CI_INSTRUCTIONS}" => "watch ci",
      "{CI_VERIFY_INSTRUCTIONS}" => "verify ci",
      "{PR_INSTRUCTIONS}" => "open pr",
      "{CI_COMMAND}" => "bin/ci"
    )
  end

  it "uses empty strings for unset fields" do
    values = described_class.new(Project.new).to_h

    expect(values.keys.size).to eq(10)
    expect(values.values).to all(eq(""))
  end
end
