require "rails_helper"

RSpec.describe Prompts::StageSections::CheckOutput do
  it "applies to implementation and pr_check stages" do
    %w[implementation pr_check].each do |type|
      expect(described_class.new(stage_type: type).to_s).to include("Running checks (CI, linters, test suites)")
    end
  end

  it "accepts symbols" do
    expect(described_class.new(stage_type: :pr_check).to_s).not_to be_empty
  end

  it "is empty for other stage types" do
    expect(described_class.new(stage_type: "task").to_s).to eq("")
  end
end
