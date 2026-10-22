require "rails_helper"

RSpec.describe Jira::TicketRows do
  it "keeps valid rows" do
    rows = [ { "key" => "PROJ-1", "summary" => "Fix it" } ]

    expect(described_class.call(rows)).to eq(rows)
  end

  it "drops non-hash rows" do
    expect(described_class.call([ nil, "PROJ-1", 4, [ "PROJ-2" ] ])).to eq([])
  end

  it "drops blank or invalid keys" do
    rows = [
      { "key" => "", "summary" => "a" },
      { "summary" => "b" },
      { "key" => "proj-1", "summary" => "c" },
      { "key" => "PROJ", "summary" => "d" },
      { "key" => "PROJ-1x", "summary" => "e" }
    ]

    expect(described_class.call(rows)).to eq([])
  end

  it "strips whitespace around keys but leaves the summary as is" do
    rows = [ { "key" => " PROJ-1\n", "summary" => "  Fix it " } ]

    expect(described_class.call(rows)).to eq([ { "key" => "PROJ-1", "summary" => "  Fix it " } ])
  end

  it "defaults a missing summary to an empty string" do
    expect(described_class.call([ { "key" => "PROJ-1" } ])).to eq([ { "key" => "PROJ-1", "summary" => "" } ])
  end
end
