class WorkflowStageOrdersController < ApplicationController
  include ProjectScoped
  include WorkflowScoped

  before_action :set_workflow

  # Adds a pipeline stage (from the stage table's menu) to a development workflow.
  def create
    if @workflow.stage_order.add!(params[:stage_type])
      redirect_to project_workflow_path(@project, @workflow), notice: "Stage added."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: "That stage can't be added: it is already there, not available for this project, or the workflow has passed that point."
    end
  end

  # Up/down arrows in the stage table.
  def move
    stage = @workflow.stages.find(params[:stage_id])
    if @workflow.stage_order.move!(stage, params[:direction])
      redirect_to project_workflow_path(@project, @workflow)
    else
      redirect_to project_workflow_path(@project, @workflow), alert: "That stage can't be moved there."
    end
  end
end
