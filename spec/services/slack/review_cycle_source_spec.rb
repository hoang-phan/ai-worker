require "rails_helper"

RSpec.describe Slack::ReviewCycleSource do
  let(:record) { double("project", update: true) }
  let(:fetcher) { instance_double(Slack::MentionFetcher, poll: nil, running?: false, last_started_at: nil, start: nil) }
  let(:sync) { instance_double(Slack::ReviewSync, fetcher: fetcher, blockers: [ "no token" ]) }
  let(:source) { described_class.new(record, log_prefix: "[Spec] project=1", sync: sync) }

  def result(created: [], failed: [])
    Slack::ReviewSync::Result.new(blockers: [], created: created, skipped: [], failed: failed, skipped_reasons: Hash.new(0))
  end

  before { allow(WorkflowSchedulerJob).to receive(:perform_later) }

  it "delegates poll, import, blockers and start!" do
    allow(fetcher).to receive(:poll).and_return([ 1 ])
    allow(sync).to receive(:import).with([ 1 ]).and_return(:imported)

    expect(source.poll).to eq([ 1 ])
    expect(source.import([ 1 ])).to eq(:imported)
    expect(source.blockers).to eq([ "no token" ])
    source.start!
    expect(fetcher).to have_received(:start)
  end

  it "appends failures to the log line" do
    expect(source.log_message(result(failed: [ "x", "y" ]), "sum")).to eq("[Spec] project=1 sum x; y")
    expect(source.log_message(result, "sum")).to eq("[Spec] project=1 sum")
  end

  it "persists to the slack_* columns" do
    freeze_time do
      source.persist!(result, "sum")
      expect(record).to have_received(:update).with(slack_last_synced_at: Time.current, slack_last_result: "sum")
    end
    source.persist_failure!("failed: x")
    expect(record).to have_received(:update).with(slack_last_result: "failed: x")
  end

  it "enqueues the scheduler after import only when workflows were created" do
    source.after_import(result)
    expect(WorkflowSchedulerJob).not_to have_received(:perform_later)
    source.after_import(result(created: [ 1 ]))
    expect(WorkflowSchedulerJob).to have_received(:perform_later).once
  end

  it "is always eligible and idle only when the fetcher is not running" do
    expect(source.eligible?).to be(true)
    expect(source.idle?).to be(true)
    allow(fetcher).to receive(:running?).and_return(true)
    expect(source.idle?).to be(false)
  end

  it "is due after FETCH_EVERY and not before" do
    expect(source.due?).to be(true)
    allow(fetcher).to receive(:last_started_at).and_return((described_class::FETCH_EVERY + 1.minute).ago)
    expect(source.due?).to be(true)
    allow(fetcher).to receive(:last_started_at).and_return((described_class::FETCH_EVERY - 1.minute).ago)
    expect(source.due?).to be(false)
  end
end
