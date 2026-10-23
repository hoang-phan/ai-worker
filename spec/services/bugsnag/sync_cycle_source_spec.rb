require "rails_helper"

RSpec.describe Bugsnag::SyncCycleSource do
  let(:record) { double("bugsnag_sync", update: true, auto_sync?: true) }
  let(:triager) { instance_double(Bugsnag::Triager, poll: nil, running?: false, last_started_at: nil, start: nil) }
  let(:sync) { instance_double(Bugsnag::TriageSync, triager: triager, blockers: [ "no clone" ]) }
  let(:source) { described_class.new(record, sync: sync) }
  let(:tuesday_10am) { Time.zone.local(2026, 10, 20, 10, 0) }

  it "persists the summary with a timestamp, and failures as last_result only" do
    freeze_time do
      source.persist!(nil, "sum")
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

  describe "#due?" do
    def due_at(time) = travel_to(time) { source.due? }

    it "is due on a weekday from RUN_HOUR when not started today" do
      expect(due_at(tuesday_10am)).to be(true)
      expect(due_at(tuesday_10am.change(hour: described_class::RUN_HOUR))).to be(true)
    end

    it "is not due before RUN_HOUR, on weekends, or after a start today" do
      expect(due_at(tuesday_10am.change(hour: described_class::RUN_HOUR - 1, min: 59))).to be(false)
      expect(due_at(Time.zone.local(2026, 10, 24, 10, 0))).to be(false)
      allow(triager).to receive(:last_started_at).and_return(tuesday_10am.change(hour: 9, min: 5))
      expect(due_at(tuesday_10am)).to be(false)
    end
  end
end
