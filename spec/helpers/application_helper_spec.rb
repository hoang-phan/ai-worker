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
end
