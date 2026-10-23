require "rails_helper"

RSpec.describe Projects::AgentLessons do
  describe "#lines" do
    it "is empty for nil and blank text" do
      expect(described_class.new(nil).lines).to eq([])
      expect(described_class.new(" \n\n").lines).to eq([])
    end

    it "strips lines and drops blank ones" do
      expect(described_class.new("  a \n\n\t\n b\n").lines).to eq(%w[a b])
    end
  end

  describe "#merge" do
    it "returns the new lessons for nil or blank text" do
      expect(described_class.new(nil).merge(%w[a b])).to eq("a\nb")
      expect(described_class.new("").merge(%w[a])).to eq("a")
    end

    it "appends new lessons after existing ones" do
      expect(described_class.new("one").merge(%w[two three])).to eq("one\ntwo\nthree")
    end

    it "skips lessons matching an existing line case-insensitively" do
      expect(described_class.new("Use partial A").merge([ "use PARTIAL a", "Other" ])).to eq("Use partial A\nOther")
    end

    it "de-duplicates within the new batch" do
      expect(described_class.new("").merge([ "Same", "same", "SAME" ])).to eq("Same")
    end

    it "strips blank lines from the stored text" do
      expect(described_class.new("a\n\n  \nb\n").merge(%w[c])).to eq("a\nb\nc")
    end

    it "keeps only the newest MAX lines" do
      text = (1..described_class::MAX).map { |i| "old #{i}" }.join("\n")

      lines = described_class.new(text).merge([ "new 1", "new 2" ]).split("\n")

      expect(lines.size).to eq(described_class::MAX)
      expect(lines.first).to eq("old 3")
      expect(lines.last(2)).to eq([ "new 1", "new 2" ])
    end
  end
end
