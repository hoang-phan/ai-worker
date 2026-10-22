require "rails_helper"

RSpec.describe StagesHelper, type: :helper do
  describe "#stage_run_mode_options" do
    let(:expected) do
      {
        "agent" => "Run the prompt with the agent",
        "message" => "Post the text to Slack"
      }
    end

    it "has an explicit label for every Stage run mode" do
      expect(expected.keys).to match_array(Stage.run_modes.keys)
    end

    it "returns label and value pairs for each run mode" do
      expect(helper.stage_run_mode_options).to eq(expected.map { |run_mode, label| [ label, run_mode ] })
    end
  end

  describe "#stage_template_options" do
    let(:project) { build_jira_project }
    let(:workflow) { build_jira_workflow(project) }
    let(:stage) { workflow.stages.find_by!(stage_type: :implementation) }

    it "lists templates of the stage type by name with their bodies in data attributes" do
      later = PromptTemplate.create!(name: "Zebra", stage_type: :implementation, body: "Later body")
      first = PromptTemplate.create!(name: "Alpha", stage_type: :implementation, body: "First body")
      PromptTemplate.create!(name: "Other", stage_type: :task, body: "Other body")

      expect(helper.stage_template_options(stage)).to eq([
        [ first.name, first.id, { data: { body: first.body } } ],
        [ later.name, later.id, { data: { body: later.body } } ]
      ])
    end
  end
end
