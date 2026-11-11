require "rails_helper"

RSpec.describe Workflows::StageOrder do
  let(:project) { build_ci_project }
  let(:workflow) { build_ci_workflow(project, status: :pending) }
  let(:order) { described_class.new(workflow) }

  def types = workflow.stage_flow.pipeline.map(&:stage_type)
  def stage(type) = Stage.find_by!(workflow: workflow, stage_type: type)

  describe "#move!" do
    it "swaps a stage with its neighbour and the pipeline follows the new order" do
      expect(order.move!(stage(:ci_verify), "up")).to be true

      expect(types).to eq %w[simple_implementation pr_create ci_verify ci_check pr_check]
    end

    it "refuses to move the first stage up or the last one down" do
      expect(order.movable?(stage(:simple_implementation), "up")).to be false
      expect(order.movable?(stage(:pr_check), "down")).to be false
      expect(order.move!(stage(:pr_check), "down")).to be false
    end

    it "only moves stages ahead of the current one in a running workflow" do
      workflow.update!(status: :ci_checking, current_stage_id: stage(:ci_check).id)

      expect(order.movable?(stage(:pr_create), "down")).to be false
      expect(order.movable?(stage(:ci_check), "down")).to be false
      expect(order.movable?(stage(:ci_verify), "up")).to be false
      expect(order.movable?(stage(:ci_verify), "down")).to be true
    end

    it "does nothing once the workflow is done" do
      workflow.update!(status: :done)

      expect(order.movable?(stage(:ci_verify), "up")).to be false
    end
  end

  describe "#add!" do
    it "offers only the missing types" do
      expect(order.addable_types).to eq []

      stage(:ci_verify).destroy
      workflow.stages.reset
      expect(order.addable_types).to eq %w[ci_verify]
    end

    it "inserts the stage at its default place and renumbers" do
      stage(:ci_verify).destroy
      workflow.stages.reset

      expect(order.add!("ci_verify")).to be true

      expect(types).to eq %w[simple_implementation pr_create ci_check ci_verify pr_check]
      expect(workflow.stages.reload.pluck(:position)).to eq [ 1, 2, 3, 4, 5 ]
    end

    it "keeps a hand-made order when adding a stage" do
      stage(:ci_verify).destroy
      workflow.stages.reset
      order.move!(stage(:pr_check), "up")
      order.move!(stage(:pr_check), "up")

      order.add!("ci_verify")

      # default slot: before the first stage that normally runs after it
      expect(types).to eq %w[simple_implementation ci_verify pr_check pr_create ci_check]
    end

    it "does not insert before the current stage of a running workflow" do
      stage(:ci_check).destroy
      workflow.stages.reset
      workflow.update!(status: :ci_verifying, current_stage_id: stage(:ci_verify).id)

      order.add!("ci_check")

      expect(types).to eq %w[simple_implementation pr_create ci_verify ci_check pr_check]
    end

    it "refuses a type already present, an unknown type, or a finished workflow" do
      expect(order.add!("pr_check")).to be false
      expect(order.add!("task")).to be false

      stage(:pr_check).destroy
      workflow.stages.reset
      workflow.update!(status: :done)
      expect(order.add!("pr_check")).to be false
    end

    it "does not offer the other implementation type" do
      stage(:simple_implementation).destroy
      workflow.stages.reset

      expect(order.addable_types).to eq %w[implementation simple_implementation]
      order.add!("implementation")
      expect(order.addable_types).not_to include("simple_implementation")
    end
  end

  it "keeps the default type order for stages that were never positioned" do
    workflow.stages.update_all(position: 0)

    expect(types).to eq %w[simple_implementation pr_create ci_check ci_verify pr_check]
  end
end
