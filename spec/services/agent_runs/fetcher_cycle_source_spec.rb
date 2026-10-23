require "rails_helper"

RSpec.describe AgentRuns::FetcherCycleSource do
  let(:fetcher) { double("fetcher", poll: [ :row ], running?: false, last_started_at: started_at, start: :started) }
  let(:sync) { double("sync", import: result, blockers: [ "missing configuration" ]) }
  let(:result) { double("result", summary: "created=1") }
  let(:started_at) { 2.hours.ago }
  let(:source) { described_class.new(sync: sync, fetcher: fetcher) }

  it "delegates polling, importing, blockers, and starting" do
    expect(source.poll).to eq([ :row ])
    expect(source.import([ :row ])).to eq(result)
    expect(source.blockers).to eq([ "missing configuration" ])
    expect(source.start!).to eq(:started)
  end

  it "uses the result summary and is idle when the fetcher is not running" do
    expect(source.summary(result)).to eq("created=1")
    expect(source.idle?).to be(true)
    allow(fetcher).to receive(:running?).and_return(true)
    expect(source.idle?).to be(false)
  end

  it "keeps the fetcher's last start time protected for cadence subclasses" do
    expect(source.send(:last_started_at)).to eq(started_at)
    expect(source).not_to respond_to(:last_started_at)
  end
end
