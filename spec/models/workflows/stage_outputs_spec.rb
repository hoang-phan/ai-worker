require "rails_helper"

RSpec.describe Workflows::StageOutputs do
  let(:project) { build_personal_project }
  let(:workflow) { build_task_workflow(project) }
  let(:stage) { workflow.stages.create!(stage_type: "runbook_step", name: "First") }
  let(:other_stage) { workflow.stages.create!(stage_type: "runbook_step", name: "Second") }

  subject(:outputs) { described_class.new(workflow) }

  describe "#all" do
    it "returns only stage_completed outputs across the stages, oldest first by id" do
      stage.log_run!("stage_completed", output: "A=1")
      other_stage.log_run!("stage_completed", output: "B=2")
      stage.log_run!("stage_completed", output: "A=3")

      expect(outputs.all).to eq(%w[A=1 B=2 A=3])
    end

    it "excludes failed and started rows" do
      stage.log_run!("started", output: "started")
      stage.log_run!("failed", error: "boom", output: "failed")
      stage.log_run!("stage_completed", output: "ok")

      expect(outputs.all).to eq(%w[ok])
    end

    it "excludes other workflows' stages" do
      stage.log_run!("stage_completed", output: "mine")
      foreign = build_task_workflow(project).stages.create!(stage_type: "runbook_step", name: "Foreign")
      foreign.log_run!("stage_completed", output: "theirs")

      expect(outputs.all).to eq(%w[mine])
    end

    it "is empty when nothing completed" do
      expect(outputs.all).to eq([])
    end
  end

  describe "#latest_for" do
    it "returns the newest stage_completed output by id" do
      stage.log_run!("stage_completed", output: "old")
      stage.log_run!("stage_completed", output: "new")
      stage.log_run!("failed", error: "boom", output: "failed")

      expect(outputs.latest_for(stage)).to eq("new")
    end

    it "breaks tied created_at by id" do
      time = Time.current
      first = stage.log_run!("stage_completed", output: "first")
      second = stage.log_run!("stage_completed", output: "second")
      StageRun.where(id: [ first.id, second.id ]).update_all(created_at: time)

      expect(outputs.latest_for(stage)).to eq("second")
    end

    it "ignores other stages' outputs" do
      other_stage.log_run!("stage_completed", output: "elsewhere")
      stage.log_run!("stage_completed", output: "here")

      expect(outputs.latest_for(stage)).to eq("here")
    end

    it "is nil for a stage with no completed run" do
      stage.log_run!("started")

      expect(outputs.latest_for(stage)).to be_nil
    end

    it "is nil for a nil stage" do
      expect(outputs.latest_for(nil)).to be_nil
    end
  end
end
