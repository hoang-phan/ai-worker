class StagesController < ApplicationController
  before_action :set_workflow
  before_action :set_stage, only: %i[edit update destroy]
  before_action :require_runbook, only: %i[new create destroy]

  def new
    @stage = @workflow.stages.new(stage_type: :runbook_step, position: @workflow.next_stage_position)
  end

  def create
    @stage = @workflow.stages.new(stage_params.merge(stage_type: :runbook_step))
    if @stage.save
      redirect_to project_workflow_path(@project, @workflow), notice: "Stage added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @stage.update(stage_params)
      redirect_to project_workflow_path(@project, @workflow), notice: "Stage updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # The stage a runbook is on (running or waiting for Next) can't be removed from under it.
  def destroy
    unless @stage.removable?
      redirect_to project_workflow_path(@project, @workflow), alert: "That is the current stage; move on first."
    else
      @stage.destroy
      redirect_to project_workflow_path(@project, @workflow), notice: "Stage removed."
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

  def require_runbook
    redirect_to project_workflow_path(@project, @workflow), alert: "Only runbook workflows have editable stage lists." unless @workflow.runbook?
  end

  def stage_params
    permitted = %i[prompt_template_id prompt]
    permitted += %i[name run_mode channel position auto_advance wait_for_workflow] if @workflow.runbook?
    params.require(:stage).permit(*permitted)
  end
end
