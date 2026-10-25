require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#time_ago_or_never" do
    it "says never for nil" do
      expect(helper.time_ago_or_never(nil)).to eq("never")
    end

    it "formats a time as '<words> ago'" do
      expect(helper.time_ago_or_never(3.hours.ago)).to eq("about 3 hours ago")
    end
  end

  describe "#last_run_summary" do
    it "says never when no run has occurred" do
      expect(helper.last_run_summary(nil, nil)).to eq("never")
    end

    it "omits a blank result" do
      expect(helper.last_run_summary(3.hours.ago, "")).to eq("about 3 hours ago")
    end

    it "includes both the time and result" do
      expect(helper.last_run_summary(3.hours.ago, "created 2")).to eq("about 3 hours ago · created 2")
    end
  end
end
