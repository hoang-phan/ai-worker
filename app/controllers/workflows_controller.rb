class WorkflowsController < ApplicationController
  include ProjectScoped
  include WorkflowScoped

  before_action :set_workflow, only: %i[show edit update destroy]

  def show
    @stage_runs = StageRun.history_for(@workflow)
  end

  def new
    @workflow = @project.workflows.new(Projects::WorkflowDefaults.new(@project).attributes(kind: params[:kind]))
  end

  def edit
  end

  def create
    @workflow = @project.workflows.new(workflow_params)
    @workflow.kind = Projects::WorkflowDefaults.kind_for(params.dig(:workflow, :kind))
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

  private

  def workflow_params
    params.require(:workflow).permit(:jira_ticket, :branch_name, :github_reviewer, :skills, :pr_skills, :task_description, :position, :variables_text, :copy_stages_from_id, :slack_review_thread_ts)
  end
end
