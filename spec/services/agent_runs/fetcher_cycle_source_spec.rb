require "rails_helper"

RSpec.describe AgentRuns::FetcherCycleSource do
  let(:fetcher) { double("fetcher", poll: [ :row ], running?: false, last_started_at: started_at, start: :started) }
  let(:sync) { double("sync", import: result, blockers: [ "missing configuration" ]) }
  let(:result) { double("result", summary: "created=1") }
  let(:now) { Time.zone.local(2026, 10, 20, 12, 0) }
  let(:started_at) { now - 2.hours }
  let(:clock) { -> { now } }
  let(:source) { described_class.new(sync: sync, fetcher: fetcher, clock: clock) }
  let(:cadenced_source_class) do
    Class.new(described_class) do
      def due?
        AgentRuns::Cadence.every(1.hour, last_started_at: last_started_at, now: now)
      end
    end
  end

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

  it "keeps the fetcher's last start time and clock protected for cadence subclasses" do
    cadenced_source = cadenced_source_class.new(sync: sync, fetcher: fetcher, clock: clock)

    expect(cadenced_source.due?).to be(true)
    expect(source).not_to respond_to(:last_started_at)
    expect(source).not_to respond_to(:now)
  end
end
