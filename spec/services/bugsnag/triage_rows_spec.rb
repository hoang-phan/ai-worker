require "rails_helper"

RSpec.describe Bugsnag::TriageRows do
  it "keeps valid rows" do
    rows = [ { "bugsnag_id" => "abc123def", "jira_key" => "PROJ-12" } ]

    expect(described_class.call(rows)).to eq(rows)
  end

  it "drops non-hash rows" do
    expect(described_class.call([ nil, "x", 3, [ "a" ] ])).to eq([])
  end

  it "drops blank or invalid ids" do
    rows = [
      { "bugsnag_id" => "", "jira_key" => "PROJ-1" },
      { "bugsnag_id" => nil, "jira_key" => "PROJ-1" },
      { "bugsnag_id" => "short", "jira_key" => "PROJ-1" },
      { "bugsnag_id" => "has space here", "jira_key" => "PROJ-1" },
      { "bugsnag_id" => "a" * 65, "jira_key" => "PROJ-1" }
    ]

    expect(described_class.call(rows)).to eq([])
  end

  it "drops blank or invalid keys" do
    rows = [
      { "bugsnag_id" => "abc123def", "jira_key" => "" },
      { "bugsnag_id" => "abc123def" },
      { "bugsnag_id" => "abc123def", "jira_key" => "proj-1" },
      { "bugsnag_id" => "abc123def", "jira_key" => "PROJ-" },
      { "bugsnag_id" => "abc123def", "jira_key" => "PROJ-1 extra" }
    ]

    expect(described_class.call(rows)).to eq([])
  end

  it "strips whitespace around ids and keys" do
    rows = [ { "bugsnag_id" => "  abc123def\n", "jira_key" => " PROJ-7 " } ]

    expect(described_class.call(rows)).to eq([ { "bugsnag_id" => "abc123def", "jira_key" => "PROJ-7" } ])
  end

  it "drops extra fields" do
    rows = [ { "bugsnag_id" => "abc123def", "jira_key" => "PROJ-7", "note" => "x" } ]

    expect(described_class.call(rows)).to eq([ { "bugsnag_id" => "abc123def", "jira_key" => "PROJ-7" } ])
  end
end
