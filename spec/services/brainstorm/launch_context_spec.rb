require "rails_helper"

RSpec.describe Brainstorm::LaunchContext do
  describe ".from_workflows" do
    it "builds newest-first brief lines and derived prompt values" do
      workflows = [ double("newest workflow", brief: "Newest brief"), double("older workflow", brief: "Older brief") ]

      context = described_class.from_workflows(workflows)

      expect(context.lines).to eq([ "- Newest brief", "- Older brief" ])
      expect(context.lines).to be_frozen
      expect(context.total).to eq(2)
      expect(context.history_text).to eq("- Newest brief\n- Older brief")
      expect(context.prompt_inputs).to eq(
        backlog_lines: [ "- Newest brief", "- Older brief" ],
        total_in_flight: 2
      )
    end

    it "keeps a frozen copy when the input lines are later mutated" do
      input_lines = [ "- Original brief" ]
      context = described_class.new(lines: input_lines)

      input_lines << "- Later brief"

      expect(context.lines).to eq([ "- Original brief" ])
    end

    it "handles no workflows" do
      context = described_class.from_workflows([])

      expect(context.lines).to eq([])
      expect(context.total).to eq(0)
      expect(context.history_text).to eq("")
      expect(context.prompt_inputs).to eq(backlog_lines: [], total_in_flight: 0)
    end
  end
end
