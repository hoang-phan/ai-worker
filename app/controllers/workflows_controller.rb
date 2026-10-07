class WorkflowsController < ApplicationController
  before_action :set_project
  before_action :set_workflow, only: %i[show edit update destroy start destroy_image]

  def show
    @stage_runs = @workflow.stages.flat_map(&:stage_runs).sort_by(&:created_at).reverse
  end

  def new
    @workflow = @project.workflows.new(position: next_position)
  end

  def edit
  end

  def create
    @workflow = @project.workflows.new(workflow_params)
    if @workflow.save
      @workflow.add_images(params.dig(:workflow, :images))
      redirect_to project_workflow_path(@project, @workflow), notice: "Workflow created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @workflow.update(workflow_params)
      @workflow.add_images(params.dig(:workflow, :images))
      redirect_to project_workflow_path(@project, @workflow), notice: "Workflow updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @workflow.destroy
    redirect_to @project, notice: "Workflow deleted."
  end

  def destroy_image
    @workflow.remove_image(params[:name])
    redirect_back_or_to edit_project_workflow_path(@project, @workflow), notice: "Image removed."
  end

  def start
    if @workflow.pending?
      @workflow.update!(status: :implementing)
      redirect_to project_workflow_path(@project, @workflow), notice: "Workflow started."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: "Workflow has already been started."
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_workflow
    @workflow = @project.workflows.find(params[:id])
  end

  def next_position
    (@project.workflows.maximum(:position) || 0) + 1
  end

  def workflow_params
    params.require(:workflow).permit(:jira_ticket, :branch_name, :github_reviewer, :skills, :task_description, :agent, :position)
  end
end
