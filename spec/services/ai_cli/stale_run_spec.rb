require "rails_helper"

RSpec.describe AiCli::StaleRun do
  let(:now) { Time.zone.parse("2026-01-01 12:00:00") }
  let(:clock) { -> { now } }
  let(:kill) { instance_double(Method, call: 1) }

  def build(started_at:, stale_after: 10.minutes)
    described_class.new(started_at: started_at, stale_after: stale_after, kill: kill, clock: clock)
  end

  describe "#stale?" do
    it "is not stale without a started_at" do
      expect(build(started_at: nil)).not_to be_stale
    end

    it "is not stale when started within stale_after" do
      expect(build(started_at: now - 5.minutes)).not_to be_stale
    end

    it "is stale when started longer ago than stale_after" do
      expect(build(started_at: now - 11.minutes)).to be_stale
    end

    it "uses Time.current by default" do
      run = described_class.new(started_at: 2.hours.ago, stale_after: 1.hour, kill: kill)
      expect(run).to be_stale
    end
  end

  describe "#terminate!" do
    it "sends TERM to the given target" do
      build(started_at: now).terminate!(-123)

      expect(kill).to have_received(:call).with("TERM", -123)
    end

    it "swallows Errno::ESRCH" do
      allow(kill).to receive(:call).and_raise(Errno::ESRCH)

      expect { build(started_at: now).terminate!(123) }.not_to raise_error
    end
  end
end
