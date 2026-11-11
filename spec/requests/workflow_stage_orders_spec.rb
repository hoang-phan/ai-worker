require "rails_helper"

RSpec.describe "WorkflowStageOrders", type: :request do
  let(:project) { build_ci_project }
  let(:workflow) { build_ci_workflow(project, status: :pending) }

  def types = workflow.stage_flow.pipeline.map(&:stage_type)

  describe "POST move_stage" do
    it "moves the stage" do
      stage = workflow.stages.find_by!(stage_type: :ci_verify)

      post move_stage_project_workflow_path(project, workflow, stage_id: stage.id, direction: "up")

      expect(response).to redirect_to(project_workflow_path(project, workflow))
      expect(types).to eq %w[simple_implementation pr_create ci_verify ci_check pr_check]
    end

    it "alerts when it can't move" do
      stage = workflow.stages.find_by!(stage_type: :pr_check)

      post move_stage_project_workflow_path(project, workflow, stage_id: stage.id, direction: "down")

      expect(flash[:alert]).to match(/can't be moved/)
    end
  end

  describe "POST add_stage" do
    it "adds a missing stage" do
      workflow.stages.find_by!(stage_type: :ci_verify).destroy

      post add_stage_project_workflow_path(project, workflow, stage_type: "ci_verify")

      expect(flash[:notice]).to eq("Stage added.")
      expect(types).to include("ci_verify")
    end

    it "refuses an existing stage" do
      post add_stage_project_workflow_path(project, workflow, stage_type: "pr_check")

      expect(flash[:alert]).to match(/can't be added/)
    end
  end

  describe "workflow page" do
    it "shows the add menu and the arrows" do
      workflow.stages.find_by!(stage_type: :ci_verify).destroy

      get project_workflow_path(project, workflow)

      expect(response.body).to include("add_stage", "move_stage", 'aria-label="Move up"')
    end
  end
end
