require "rails_helper"

RSpec.describe Jira::AgentFetcher do
  it "keeps only rows whose key matches KEY" do
    Dir.mktmpdir do |tmp|
      stub_const("Jira::AgentFetcher::ROOT", Pathname(tmp))
      fetcher = described_class.new(double(id: 1, project: double))
      FileUtils.mkdir_p(Pathname(tmp).join("1"))
      Pathname(tmp).join("1", "pid").write("1")
      Pathname(tmp).join("1", "tickets.json").write([
        { key: "UNS-1", summary: "ok" }, { key: "bad key", summary: "x" }, { key: "uns-2" }, "junk"
      ].to_json)
      allow(AiCli::Runner).to receive(:poll).and_return([ :completed, nil ])

      expect(fetcher.poll).to eq([ { "key" => "UNS-1", "summary" => "ok" } ])
    end
  end
end
