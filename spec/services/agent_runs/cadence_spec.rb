require "rails_helper"

RSpec.describe AgentRuns::Cadence do
  describe ".every" do
    let(:now) { Time.zone.local(2026, 10, 21, 12, 0, 0) }

    def due?(last_started_at)
      described_class.every(3.hours, last_started_at: last_started_at, now: now)
    end

    it "is due when never started" do
      expect(due?(nil)).to be(true)
    end

    it "is not due just before the interval boundary" do
      expect(due?(now - 3.hours + 1.second)).to be(false)
    end

    it "is due exactly at the interval boundary" do
      expect(due?(now - 3.hours)).to be(true)
    end

    it "is due after the interval boundary" do
      expect(due?(now - 3.hours - 1.second)).to be(true)
    end

    it "defaults now to Time.current" do
      travel_to(now) do
        expect(described_class.every(3.hours, last_started_at: now - 3.hours)).to be(true)
        expect(described_class.every(3.hours, last_started_at: now - 2.hours)).to be(false)
      end
    end
  end

  describe ".daily_on_weekdays" do
    let(:wednesday) { Time.zone.local(2026, 10, 21, 10, 0, 0) }

    def due?(now, last_started_at = nil)
      described_class.daily_on_weekdays(hour: 9, last_started_at: last_started_at, now: now)
    end

    it "is due on a weekday after the hour when never started" do
      expect(due?(wednesday)).to be(true)
    end

    it "is due exactly at the hour" do
      expect(due?(Time.zone.local(2026, 10, 21, 9, 0, 0))).to be(true)
    end

    it "is not due before the hour" do
      expect(due?(Time.zone.local(2026, 10, 21, 8, 59, 59))).to be(false)
    end

    it "is not due on Saturday" do
      expect(due?(Time.zone.local(2026, 10, 24, 10, 0, 0))).to be(false)
    end

    it "is not due on Sunday" do
      expect(due?(Time.zone.local(2026, 10, 25, 10, 0, 0))).to be(false)
    end

    it "is not due when already started today" do
      expect(due?(wednesday, Time.zone.local(2026, 10, 21, 9, 5, 0))).to be(false)
    end

    it "is due when started yesterday" do
      expect(due?(wednesday, Time.zone.local(2026, 10, 20, 9, 5, 0))).to be(true)
    end

    it "treats a start at midnight today as already started today" do
      expect(due?(wednesday, wednesday.beginning_of_day)).to be(false)
    end

    it "defaults now to Time.zone.now" do
      travel_to(wednesday) { expect(described_class.daily_on_weekdays(hour: 9, last_started_at: nil)).to be(true) }
    end
  end
end
