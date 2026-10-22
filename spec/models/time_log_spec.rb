require "rails_helper"

RSpec.describe TimeLog, type: :model do
  def log(key, seconds, **attrs)
    TimeLog.create!(ticket_key: key, seconds: seconds, started_at: Time.current, **attrs)
  end

  describe "validations" do
    it "is valid with a ticket_key, started_at and positive integer seconds" do
      expect(TimeLog.new(ticket_key: "TL-1", seconds: 60, started_at: Time.current)).to be_valid
    end

    it "requires ticket_key and started_at" do
      record = TimeLog.new(seconds: 60)
      expect(record).not_to be_valid
      expect(record.errors).to include(:ticket_key, :started_at)
    end

    it "requires seconds to be a positive integer" do
      [0, -5, 1.5, nil].each do |value|
        expect(TimeLog.new(ticket_key: "TL-1", started_at: Time.current, seconds: value)).not_to be_valid
      end
    end
  end

  describe ".seconds_by_ticket" do
    it "sums seconds per requested ticket key" do
      log("TLSPEC-1", 1800)
      log("TLSPEC-1", 900)
      log("TLSPEC-2", 3600)
      log("TLSPEC-3", 60)

      expect(TimeLog.seconds_by_ticket(%w[TLSPEC-1 TLSPEC-2])).to eq("TLSPEC-1" => 2700, "TLSPEC-2" => 3600)
    end

    it "ignores blank keys and returns {} for empty input" do
      log("TLSPEC-1", 60)

      expect(TimeLog.seconds_by_ticket([nil, "", "TLSPEC-1"])).to eq("TLSPEC-1" => 60)
      expect(TimeLog.seconds_by_ticket([nil, ""])).to eq({})
      expect(TimeLog.seconds_by_ticket([])).to eq({})
      expect(TimeLog.seconds_by_ticket(nil)).to eq({})
    end
  end

  describe ".seconds_for" do
    it "sums seconds for one ticket and returns 0 when none or blank" do
      log("TLSPEC-1", 1800)
      log("TLSPEC-1", 900)

      expect(TimeLog.seconds_for("TLSPEC-1")).to eq(2700)
      expect(TimeLog.seconds_for("TLSPEC-NONE")).to eq(0)
      expect(TimeLog.seconds_for(nil)).to eq(0)
      expect(TimeLog.seconds_for("")).to eq(0)
    end
  end
end
