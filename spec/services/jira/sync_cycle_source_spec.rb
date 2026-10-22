require "rails_helper"

RSpec.describe Jira::SyncCycleSource do
  let(:record) { double("jira_sync", update: true, auto_sync?: true) }
  let(:fetcher) { instance_double(Jira::AgentFetcher, poll: nil, running?: false, last_started_at: nil, start: nil) }
  let(:sync) { instance_double(Jira::TicketSync, fetcher: fetcher, blockers: []) }
  let(:source) { described_class.new(record, log_prefix: "[Spec] jira_sync=1", sync: sync) }
  let(:result) { Jira::TicketSync::Result.new(blockers: [], created: [ "A-1" ], skipped: [], failed: [ "A-2: boom", "A-3: bad" ]) }

  it "delegates poll, import, blockers and start! to the sync and fetcher" do
    allow(fetcher).to receive(:poll).and_return([ 1 ])
    allow(sync).to receive(:import).with([ 1 ]).and_return(result)

    expect(source.poll).to eq([ 1 ])
    expect(source.import([ 1 ])).to eq(result)
    expect(source.blockers).to eq([])
    source.start!
    expect(fetcher).to have_received(:start)
  end

  it "appends failures to the log line" do
    expect(source.log_message(result, "sum")).to eq("[Spec] jira_sync=1 sum A-2: boom; A-3: bad")
    expect(source.log_message(result.dup.tap { |r| r.failed = [] }, "sum")).to eq("[Spec] jira_sync=1 sum")
  end

  it "persists the summary with a timestamp, and failures as last_result only" do
    freeze_time do
      source.persist!(result, "sum")
      expect(record).to have_received(:update).with(last_synced_at: Time.current, last_result: "sum")
    end
    source.persist_failure!("failed: x")
    expect(record).to have_received(:update).with(last_result: "failed: x")
  end

  it "is eligible only for auto-sync records" do
    expect(source.eligible?).to be(true)
    allow(record).to receive(:auto_sync?).and_return(false)
    expect(source.eligible?).to be(false)
  end

  it "is idle only when the fetcher is not running" do
    expect(source.idle?).to be(true)
    allow(fetcher).to receive(:running?).and_return(true)
    expect(source.idle?).to be(false)
  end

  describe "#due?" do
    it "is due when never started" do
      expect(source.due?).to be(true)
    end

    it "is due after FETCH_EVERY and not before" do
      allow(fetcher).to receive(:last_started_at).and_return((described_class::FETCH_EVERY + 1.minute).ago)
      expect(source.due?).to be(true)
      allow(fetcher).to receive(:last_started_at).and_return((described_class::FETCH_EVERY - 1.minute).ago)
      expect(source.due?).to be(false)
    end
  end
end
