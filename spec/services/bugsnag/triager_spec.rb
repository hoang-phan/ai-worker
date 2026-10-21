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

  describe ".summary" do
    it "lists the newly added keys" do
      expect(described_class.summary(%w[UNS-1 UNS-2])).to eq("2 new ticket(s): UNS-1, UNS-2")
    end

    it "says nothing new when no keys were added" do
      expect(described_class.summary([])).to eq("nothing new")
    end
  end
end
