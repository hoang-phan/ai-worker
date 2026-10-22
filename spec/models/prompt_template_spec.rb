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

  describe "model and effort" do
    let(:template) { PromptTemplate.new(name: "Agent", stage_type: :task, body: "Do {TASK}") }

    it "allows blank values" do
      template.model = ""
      template.effort = ""
      expect(template).to be_valid
    end

    it "accepts known efforts and model ids" do
      PromptTemplate::EFFORTS.each do |effort|
        template.effort = effort
        template.model = "claude-opus-5-5[1m]"
        expect(template).to be_valid
      end
    end

    it "rejects an unknown effort" do
      template.effort = "extreme"
      expect(template).not_to be_valid
      expect(template.errors[:effort]).to be_present
    end

    it "rejects a model with spaces or shell characters" do
      [ "claude sonnet", "x;rm -rf" ].each do |model|
        template.model = model
        expect(template).not_to be_valid
        expect(template.errors[:model]).to be_present
      end
    end
  end
end
