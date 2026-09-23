class StagesController < ApplicationController
  before_action :set_workflow
  before_action :set_stage

  def edit
  end

  def update
    if @stage.update(stage_params)
      redirect_to project_workflow_path(@project, @workflow), notice: "Stage updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_workflow
    @project = Project.find(params[:project_id])
    @workflow = @project.workflows.find(params[:workflow_id])
  end

  def set_stage
    @stage = @workflow.stages.find(params[:id])
  end

  def stage_params
    params.require(:stage).permit(:prompt_template_id, :prompt)
  end
end
