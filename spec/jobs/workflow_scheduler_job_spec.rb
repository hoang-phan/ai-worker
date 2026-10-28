require "rails_helper"

RSpec.describe WorkflowSchedulerJob, type: :job do
  let(:tick) { instance_double(Scheduling::Tick) }

  it "forwards the named workflow id to the injected tick" do
    expect(tick).to receive(:call).with(42)

    described_class.perform_now(42, tick: tick)
  end

  it "uses Scheduling::Capacity.default_max for max_concurrent_agents" do
    expect(described_class.max_concurrent_agents).to eq(Scheduling::Capacity.default_max)
  end

  it "runs on the stage_execution queue" do
    expect(described_class.queue_name).to eq("stage_execution")
  end
end
