require "rails_helper"

RSpec.describe BadgesHelper, type: :helper do
  describe "#badge" do
    it "uses the neutral tone by default" do
      expect(helper.badge("Pending")).to eq('<span class="badge badge-neutral">Pending</span>')
    end

    it "renders an explicit tone" do
      expect(helper.badge("Done", :success)).to eq('<span class="badge badge-success">Done</span>')
    end

    it "passes extra options to the span" do
      expect(helper.badge("Logged", :info, title: "Details")).to eq('<span class="badge badge-info" title="Details">Logged</span>')
    end

    it "rejects an unknown tone" do
      expect { helper.badge("Unknown", :purple) }.to raise_error(ArgumentError, "Unknown badge tone: purple")
    end
  end
end
