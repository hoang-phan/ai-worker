class StageDefinitionsController < ApplicationController
  before_action :set_project
  before_action :set_definition, only: %i[edit update destroy]

  def new
    @definition = @project.stage_definitions.new(position: (@project.stage_definitions.maximum(:position) || 0) + 1)
  end

  def create
    @definition = @project.stage_definitions.new(definition_params)
    if @definition.save
      redirect_to @project, notice: "Stage added. New workflows copy it; existing workflows keep their own stages."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @definition.update(definition_params)
      redirect_to @project, notice: "Stage updated. Existing workflows keep their own copy."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @definition.destroy
    redirect_to @project, notice: "Stage removed."
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_definition
    @definition = @project.stage_definitions.find(params[:id])
  end

  def definition_params
    params.require(:stage_definition).permit(:name, :position, :run_mode, :channel, :prompt)
  end
end
