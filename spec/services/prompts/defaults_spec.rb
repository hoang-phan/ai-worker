require "rails_helper"

RSpec.describe Prompts::Defaults do
  # marker: the result line the agent must print; placeholders: tokens the body must carry;
  # sha256: digest of the body as of the move out of defaults.rb (any wording change must update it on purpose).
  BODY_EXPECTATIONS = {
    "pr_review" => {
      marker: nil,
      placeholders: %w[{PR} {SLACK}],
      sha256: "14dd3571ccf7f58c4b25f8a4861b332ba4a81d19b49df952376f1c3a14ed3e9f"
    },
    "jira_update" => {
      marker: "JIRA_RESULT",
      placeholders: %w[{JIRA} {PR} {TESTER}],
      sha256: "4a2e5de310d1ae675d40b06603856d13b4d3cfbab3bc1fe228aac2cc76eec6c0"
    },
    "uat_test" => {
      marker: "UAT_RESULT",
      placeholders: %w[{JIRA} {PR} {UAT_URL} {TEST_INSTRUCTIONS} {UAT_INSTRUCTIONS}],
      sha256: "6fac8c40b2923970f75511da4d219edbbd93135328d40c80b17c69fea26b61b6"
    },
    "local_test" => {
      marker: "LOCAL_TEST_RESULT",
      placeholders: %w[{JIRA} {PR} {LOCAL_URL} {TEST_INSTRUCTIONS} {LOCAL_INSTRUCTIONS}],
      sha256: "cff34d893ea8661dac04a267ce5bde84c764a7eeef38b9e6bab9b1bf508b519f"
    },
    "simple_implementation" => {
      marker: nil,
      placeholders: %w[{SKILLS} {JIRA}],
      sha256: "e27137f080bd37e7acf61e559b86bf7cc1d8f0241a341af446bfcae6b0a9f47d"
    },
    "ci_verify" => {
      marker: "CI_VERDICT",
      placeholders: %w[{JIRA} {CI_COMMAND} {CI_STATUS} {CI_OUTPUT} {CI_VERIFY_INSTRUCTIONS}],
      sha256: "fe950a34ffd9a37f0e27134299bb5fdad0197db9f6660fb47a3ccc6526b0b05a"
    },
    "pr_create" => {
      marker: nil,
      placeholders: %w[{JIRA} {PR_SKILLS} {REVIEWER} {PR_INSTRUCTIONS}],
      sha256: "a7e20380e3323350cf3b5a71a5080b29350ccb93e759534a391ef55c50e581a5"
    }
  }.freeze

  BODY_EXPECTATIONS.each do |type, expected|
    describe ".for(#{type.inspect})" do
      subject(:body) { described_class.for(type) }

      it "returns a non-empty, frozen body ending with a newline" do
        expect(body).to be_present
        expect(body).to be_frozen
        expect(body).to end_with("\n")
      end

      it "tells the agent to print #{expected[:marker]}" do
        expect(body).to include("`#{expected[:marker]}:") if expected[:marker]
      end

      it "contains its placeholders" do
        expected[:placeholders].each { |placeholder| expect(body).to include(placeholder) }
      end

      it "is unchanged since it was pinned" do
        expect(Digest::SHA256.hexdigest(body)).to eq(expected[:sha256])
      end

      it "accepts a symbol" do
        expect(described_class.for(type.to_sym)).to equal(body)
      end
    end
  end

  %w[implementation pr_check task runbook_step].each do |type|
    it "returns nil for #{type}" do
      expect(described_class.for(type)).to be_nil
    end
  end

  it "returns nil for nil" do
    expect(described_class.for(nil)).to be_nil
  end
end
