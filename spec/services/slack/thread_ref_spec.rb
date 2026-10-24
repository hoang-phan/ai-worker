require "rails_helper"

RSpec.describe Slack::ThreadRef do
  describe ".ts_for" do
    it "keeps a bare thread timestamp" do
      expect(described_class.ts_for("1760000000.123456")).to eq("1760000000.123456")
    end

    it "extracts a timestamp from a permalink with or without a thread query" do
      link = "https://acme.slack.com/archives/C123ABC/p1760000000123456"

      expect(described_class.ts_for(link)).to eq("1760000000.123456")
      expect(described_class.ts_for("#{link}?thread_ts=1760000000.123456&cid=C123ABC")).to eq("1760000000.123456")
    end

    it "strips surrounding whitespace and returns nil for blank input" do
      expect(described_class.ts_for("  bare-thread  \n")).to eq("bare-thread")
      expect(described_class.ts_for("  \n")).to be_nil
      expect(described_class.ts_for(nil)).to be_nil
    end
  end

  describe "PERMALINK" do
    it "matches Slack message permalinks with an optional query" do
      link = "https://acme.slack.com/archives/C123ABC/p1760000000123456"

      expect(link).to match(described_class::PERMALINK)
      expect("#{link}?thread_ts=1760000000.123456").to match(described_class::PERMALINK)
    end
  end
end
