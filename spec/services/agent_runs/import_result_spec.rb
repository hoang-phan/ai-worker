require "rails_helper"

RSpec.describe AgentRuns::ImportResult do
  describe ".empty" do
    it "builds empty collections and a skipped-reasons counter" do
      result = described_class.empty([ "missing setup" ])

      expect(result).to have_attributes(blockers: [ "missing setup" ], created: [], skipped: [], failed: [], skipped_reasons: {})
      expect(result.skipped_reasons.default).to eq(0)
    end
  end

  describe "#summary" do
    it "counts created, skipped and failed" do
      result = described_class.new(blockers: [], created: %w[A-1 A-2], skipped: %w[A-3], failed: [])

      expect(result.summary).to eq("created 2, skipped 1, failed 0")
    end

    it "appends the skipped reasons breakdown" do
      result = described_class.new(
        blockers: [], created: [ 1 ], skipped: %w[a b c], failed: [ "x" ], skipped_reasons: { "merged" => 2, "already imported" => 1 }
      )

      expect(result.summary).to eq("created 1, skipped 3 (2 merged, 1 already imported), failed 1")
    end

    it "treats nil skipped reasons as empty" do
      result = described_class.new(blockers: [], created: [], skipped: [], failed: [], skipped_reasons: nil)

      expect(result.summary).to eq("created 0, skipped 0, failed 0")
    end
  end

  describe "#record_save" do
    it "records a successfully saved label" do
      record = instance_double(Workflow, save: true)
      result = described_class.empty

      result.record_save(record, "UNS-1")

      expect(result.created).to eq([ "UNS-1" ])
      expect(result.failed).to be_empty
    end

    it "records validation errors for a failed save" do
      errors = instance_double(ActiveModel::Errors, full_messages: [ "Bad", "Worse" ])
      record = instance_double(Workflow, save: false, errors: errors)
      result = described_class.empty

      result.record_save(record, "UNS-1")

      expect(result.created).to be_empty
      expect(result.failed).to eq([ "UNS-1: Bad and Worse" ])
    end
  end
end
