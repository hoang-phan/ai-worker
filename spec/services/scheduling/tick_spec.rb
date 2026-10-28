require "rails_helper"

RSpec.describe Scheduling::Tick do
  let(:max_capacity) { 7 }
  let(:events) { [] }
  let(:active_runner) { instance_double(Scheduling::ActiveWorkflowRunner) }
  let(:post_merge_phase) { instance_double(Scheduling::PostMergePhase) }
  let(:uat_phase) { instance_double(Scheduling::UatPhase) }

  describe "#call" do
    it "runs the scheduler phases in order and forwards the named workflow" do
      allow(active_runner).to receive(:call) { |workflow_id| events << [ :active_runner_called, workflow_id ] }
      allow(post_merge_phase).to receive(:call) { events << :post_merge_phase_called }
      allow(uat_phase).to receive(:call) { events << :uat_phase_called }

      described_class.new(
        max_capacity: max_capacity,
        active_runner: active_runner,
        post_merge_phase: post_merge_phase,
        uat_phase: uat_phase
      ).call(42)

      expect(events).to eq([
        [ :active_runner_called, 42 ],
        :post_merge_phase_called,
        :uat_phase_called
      ])
    end

    it "builds default phases with max_capacity" do
      tick = described_class.new(max_capacity: max_capacity)

      expect(tick.active_runner).to be_a(Scheduling::ActiveWorkflowRunner)
      expect(tick.active_runner.max_capacity).to eq(max_capacity)
      expect(tick.post_merge_phase).to be_a(Scheduling::PostMergePhase)
      expect(tick.uat_phase).to be_a(Scheduling::UatPhase)
      expect(tick.uat_phase.max_capacity).to eq(max_capacity)
    end
  end
end
