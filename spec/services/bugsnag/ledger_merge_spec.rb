require "rails_helper"

RSpec.describe Bugsnag::LedgerMerge do
  def row(id, key) = { "bugsnag_id" => id, "jira_key" => key }

  it "adds new ids and returns their keys" do
    ledger, added = described_class.call({ "old000" => "PROJ-1" }, [ row("new111", "PROJ-2"), row("new222", "PROJ-3") ])

    expect(ledger).to eq("old000" => "PROJ-1", "new111" => "PROJ-2", "new222" => "PROJ-3")
    expect(added).to eq(%w[PROJ-2 PROJ-3])
  end

  it "skips ids already in the ledger and keeps their key" do
    ledger, added = described_class.call({ "old000" => "PROJ-1" }, [ row("old000", "PROJ-9") ])

    expect(ledger).to eq("old000" => "PROJ-1")
    expect(added).to eq([])
  end

  it "keeps the first key when an id repeats within rows" do
    ledger, added = described_class.call({}, [ row("new111", "PROJ-2"), row("new111", "PROJ-3") ])

    expect(ledger).to eq("new111" => "PROJ-2")
    expect(added).to eq(%w[PROJ-2])
  end

  it "does not modify the given ledger" do
    original = { "old000" => "PROJ-1" }

    described_class.call(original, [ row("new111", "PROJ-2") ])

    expect(original).to eq("old000" => "PROJ-1")
  end

  it "handles no rows" do
    expect(described_class.call({ "a" => "B-1" }, [])).to eq([ { "a" => "B-1" }, [] ])
  end
end
