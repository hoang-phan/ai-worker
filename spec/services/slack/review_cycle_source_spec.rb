require "rails_helper"

RSpec.describe Slack::ReviewCycleSource do
  let(:record) { double("project", update: true) }
  let(:fetcher) { instance_double(Slack::MentionFetcher, poll: nil, running?: false, last_started_at: nil, start: nil) }
  let(:sync) { instance_double(Slack::ReviewSync, fetcher: fetcher, blockers: [ "no token" ]) }
  let(:now) { Time.zone.local(2026, 10, 20, 12, 0) }
  let(:clock) { -> { now } }
  let(:source) { described_class.new(record, sync: sync, clock: clock) }

  def result(created: [], failed: [])
    Slack::ReviewSync::Result.new(blockers: [], created: created, skipped: [], failed: failed, skipped_reasons: Hash.new(0))
  end

  before { allow(WorkflowSchedulerJob).to receive(:perform_later) }

  it "appends failures to the log line" do
    expect(source.log_detail(result(failed: [ "x", "y" ]))).to eq("x; y")
    expect(source.log_detail(result)).to eq("")
  end

  it "persists to the slack_* columns" do
    source.persist!(result, "sum")
    expect(record).to have_received(:update).with(slack_last_synced_at: now, slack_last_result: "sum")
    source.persist_failure!("failed: x")
    expect(record).to have_received(:update).with(slack_last_result: "failed: x")
  end

  it "enqueues the scheduler after import only when workflows were created" do
    source.after_import(result)
    expect(WorkflowSchedulerJob).not_to have_received(:perform_later)
    source.after_import(result(created: [ 1 ]))
    expect(WorkflowSchedulerJob).to have_received(:perform_later).once
  end

  it "rescues its FetchError and AiCli::CommandError" do
    expect(source.rescue_errors).to equal(described_class::RESCUE_ERRORS)
    expect(described_class::RESCUE_ERRORS).to eq([ Slack::FetchError, AiCli::CommandError ]).and be_frozen
  end

  it "is always eligible" do
    expect(source.eligible?).to be(true)
  end

  it "is due after FETCH_EVERY and not before" do
    expect(source.due?).to be(true)
    allow(fetcher).to receive(:last_started_at).and_return(now - (described_class::FETCH_EVERY + 1.minute))
    expect(source.due?).to be(true)
    allow(fetcher).to receive(:last_started_at).and_return(now - (described_class::FETCH_EVERY - 1.minute))
    expect(source.due?).to be(false)
  end
end
