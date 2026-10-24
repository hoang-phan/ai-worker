require "rails_helper"

RSpec.describe Jira::SyncCycleSource do
  let(:record) { double("jira_sync", update: true, auto_sync?: true) }
  let(:fetcher) { instance_double(Jira::AgentFetcher, poll: nil, running?: false, last_started_at: nil, start: nil) }
  let(:sync) { instance_double(Jira::TicketSync, fetcher: fetcher, blockers: []) }
  let(:source) { described_class.new(record, sync: sync) }
  let(:result) { Jira::TicketSync::Result.new(blockers: [], created: [ "A-1" ], skipped: [], failed: [ "A-2: boom", "A-3: bad" ]) }

  it "appends failures to the log line" do
    expect(source.log_detail(result)).to eq("A-2: boom; A-3: bad")
    expect(source.log_detail(result.dup.tap { |r| r.failed = [] })).to eq("")
  end

  it "persists the summary with a timestamp, and failures as last_result only" do
    freeze_time do
      source.persist!(result, "sum")
      expect(record).to have_received(:update).with(last_synced_at: Time.current, last_result: "sum")
    end
    source.persist_failure!("failed: x")
    expect(record).to have_received(:update).with(last_result: "failed: x")
  end

  it "rescues its FetchError and AiCli::CommandError" do
    expect(source.rescue_errors).to equal(described_class::RESCUE_ERRORS)
    expect(described_class::RESCUE_ERRORS).to eq([ Jira::FetchError, AiCli::CommandError ]).and be_frozen
  end

  it "is eligible only for auto-sync records" do
    expect(source.eligible?).to be(true)
    allow(record).to receive(:auto_sync?).and_return(false)
    expect(source.eligible?).to be(false)
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
