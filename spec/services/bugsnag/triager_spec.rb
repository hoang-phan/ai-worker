require "rails_helper"

RSpec.describe Bugsnag::Triager do
  it "needs a valid bugsnag id and jira key" do
    Dir.mktmpdir do |tmp|
      stub_const("Bugsnag::Triager::ROOT", Pathname(tmp))
      triager = described_class.new(double(id: 1, project: double))
      FileUtils.mkdir_p(Pathname(tmp).join("1"))
      Pathname(tmp).join("1", "pid").write("1")
      Pathname(tmp).join("1", "result.json").write([
        { bugsnag_id: "abc123def456", jira_key: "UNS-12" },
        { bugsnag_id: "short", jira_key: "UNS-13" },
        { bugsnag_id: "abc123def456", jira_key: "bad" },
        "junk"
      ].to_json)
      allow(AiCli::Runner).to receive(:poll).and_return([ :completed, nil ])

      expect(triager.poll).to eq([ { "bugsnag_id" => "abc123def456", "jira_key" => "UNS-12" } ])
    end
  end
end
