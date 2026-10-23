require "rails_helper"

RSpec.describe Jira::WorklogError do
  it "passes its message through and defaults reason to nil" do
    error = described_class.new("Jira is unavailable")

    expect(error.message).to eq("Jira is unavailable")
    expect(error.reason).to be_nil
    expect(error).not_to be_missing_credentials
  end

  it "recognizes only the missing_credentials reason" do
    expect(described_class.new("credentials missing", reason: :missing_credentials)).to be_missing_credentials
    expect(described_class.new("another error", reason: :transport_error)).not_to be_missing_credentials
  end

  it "is rescued as a StandardError" do
    rescued = begin
      raise described_class, "Jira is unavailable"
    rescue StandardError => error
      error
    end

    expect(rescued).to be_a(StandardError)
    expect(rescued).to be_a(described_class)
  end
end
