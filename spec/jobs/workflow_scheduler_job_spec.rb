require "rails_helper"

RSpec.describe WorkflowSchedulerJob, type: :job do
  let(:max_agents) { 7 }
  let(:tick) { instance_double(Scheduling::Tick) }

  before do
    allow(described_class).to receive(:max_concurrent_agents).and_return(max_agents)
  end

  it "forwards the named workflow id and max_concurrent_agents to Scheduling::Tick" do
    allow(Scheduling::Tick).to receive(:new).with(max_capacity: max_agents).and_return(tick)
    expect(tick).to receive(:call).with(42)

    described_class.perform_now(42)
  end

  it "forwards max_concurrent_agents to Scheduling::Capacity.default_max" do
    allow(described_class).to receive(:max_concurrent_agents).and_call_original
    allow(Scheduling::Capacity).to receive(:default_max).and_return(5)

    expect(described_class.max_concurrent_agents).to eq(5)
  end

  it "runs on the stage_execution queue" do
    expect(described_class.queue_name).to eq("stage_execution")
  end
end
