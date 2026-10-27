require "rails_helper"

RSpec.describe WorkflowSchedulerJob, type: :job do
  let(:max_agents) { 7 }
  let(:events) { [] }
  let(:active_runner) { instance_double(Scheduling::ActiveWorkflowRunner) }
  let(:post_merge_phase) { instance_double(Scheduling::PostMergePhase) }
  let(:uat_phase) { instance_double(Scheduling::UatPhase) }

  before do
    allow(described_class).to receive(:max_concurrent_agents).and_return(max_agents)
    allow(Scheduling::ActiveWorkflowRunner).to receive(:new).with(max_capacity: max_agents) do
      events << :active_runner_initialized
      active_runner
    end
    allow(Scheduling::PostMergePhase).to receive(:new) do
      events << :post_merge_phase_initialized
      post_merge_phase
    end
    allow(Scheduling::UatPhase).to receive(:new).with(max_capacity: max_agents) do
      events << :uat_phase_initialized
      uat_phase
    end
    allow(active_runner).to receive(:call) { |workflow_id| events << [ :active_runner_called, workflow_id ] }
    allow(post_merge_phase).to receive(:call) { events << :post_merge_phase_called }
    allow(uat_phase).to receive(:call) { events << :uat_phase_called }
  end

  it "runs the scheduler phases in order and forwards the named workflow" do
    described_class.perform_now(42)

    expect(events).to eq([
      :active_runner_initialized,
      [ :active_runner_called, 42 ],
      :post_merge_phase_initialized,
      :post_merge_phase_called,
      :uat_phase_initialized,
      :uat_phase_called
    ])
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
