require "rails_helper"

RSpec.describe PromptTemplate do
  it "shares the stage_type mapping with Stage" do
    expect(PromptTemplate.stage_types).to eq(Stage.stage_types)
  end

  it "requires a name and a body" do
    template = PromptTemplate.new(stage_type: :task)
    expect(template).not_to be_valid
    expect(template.errors[:name]).to be_present
    expect(template.errors[:body]).to be_present

    template.name = "Plain"
    template.body = "Do {TASK}"
    expect(template).to be_valid
  end
end
