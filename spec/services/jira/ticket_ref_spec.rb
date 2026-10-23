require "rails_helper"

RSpec.describe Jira::TicketRef do
  describe ".branch_name_for" do
    it "extracts the key from a browse URL" do
      expect(described_class.branch_name_for("https://x.atlassian.net/browse/UIUX-3456")).to eq("UIUX-3456")
    end

    it "drops query, fragment and trailing path" do
      %w[?focusedId=1 #comment-2 /extra/path].each do |suffix|
        expect(described_class.branch_name_for("https://x.atlassian.net/browse/UIUX-3456#{suffix}")).to eq("UIUX-3456")
      end
    end

    it "returns a bare key unchanged" do
      expect(described_class.branch_name_for("UIUX-3456")).to eq("UIUX-3456")
    end

    it "returns nil for blank input" do
      expect(described_class.branch_name_for(nil)).to be_nil
    end
  end

  describe ".key_for" do
    it "returns the key for URLs with query, fragment or trailing path" do
      expect(described_class.key_for("https://x.atlassian.net/browse/ABC-12?x=1")).to eq("ABC-12")
      expect(described_class.key_for("https://x.atlassian.net/browse/ABC-12#c")).to eq("ABC-12")
      expect(described_class.key_for("https://x.atlassian.net/browse/ABC-12/more")).to eq("ABC-12")
    end

    it "returns bare keys" do
      expect(described_class.key_for("ABC-12")).to eq("ABC-12")
    end

    it "returns nil for lowercase or invalid input" do
      expect(described_class.key_for("abc-12")).to be_nil
      expect(described_class.key_for("https://x.atlassian.net/browse/nope")).to be_nil
      expect(described_class.key_for("")).to be_nil
      expect(described_class.key_for(nil)).to be_nil
    end
  end

  describe "KEY / .key?" do
    it "accepts exactly one valid key" do
      expect(described_class.key?("UIUX-3456")).to be(true)
      expect("UIUX-3456").to match(described_class::KEY)
    end

    it "rejects lowercase keys, a missing number and surrounding text" do
      expect(described_class.key?("uiux-3456")).to be(false)
      expect(described_class.key?("UIUX-")).to be(false)
      expect(described_class.key?("see UIUX-3456")).to be(false)
      expect(described_class.key?("UIUX-3456\nfoo")).to be(false)
      expect(described_class.key?(nil)).to be(false)
    end
  end

  describe ".url_for" do
    it "builds a browse URL with or without a trailing slash on the base" do
      expect(described_class.url_for("https://x.atlassian.net", "ABC-1")).to eq("https://x.atlassian.net/browse/ABC-1")
      expect(described_class.url_for("https://x.atlassian.net/", "ABC-1")).to eq("https://x.atlassian.net/browse/ABC-1")
    end
  end
end
