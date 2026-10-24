require "rails_helper"

RSpec.describe AgentRuns::CycleSource do
  subject(:source) { described_class.new }

  it "has default gates, hooks, logging, and rescue errors" do
    expect(source).to be_eligible
    expect(source).to be_idle
    expect(source).to be_due
    expect(source.blockers).to eq([])
    expect(source.rescue_errors).to eq([ AiCli::CommandError ])
    expect(source.log_detail("result")).to be_nil
    expect(source.after_import("result")).to be_nil
    expect(source.after_start).to be_nil
  end
end
