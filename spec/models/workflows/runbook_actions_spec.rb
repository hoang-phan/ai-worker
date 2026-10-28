require "rails_helper"

RSpec.describe Workflows::RunbookActions do
  let(:navigator) { instance_double(Workflows::RunbookNavigator) }
  let(:actions) { described_class.new(navigator) }

  it "maps Workflow's public names to the navigator" do
    expect(navigator).to receive(:start!).and_return(:started)
    expect(navigator).to receive(:advance!).and_return(:advanced)
    expect(navigator).to receive(:next_stage).and_return(:next_stage)
    expect(navigator).to receive(:previous_stage).and_return(:previous_stage)

    expect(actions.start_runbook!).to eq(:started)
    expect(actions.advance!).to eq(:advanced)
    expect(actions.next_runbook_stage).to eq(:next_stage)
    expect(actions.previous_runbook_stage).to eq(:previous_stage)
  end
end
