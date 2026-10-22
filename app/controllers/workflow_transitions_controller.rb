class WorkflowTransitionsController < ApplicationController
  include ProjectScoped
  include WorkflowScoped

  before_action :set_workflow

  def start
    # Started from the project list: go back to it with the status filter kept.
    fallback = params[:status].present? ? project_path(@project, status: params[:status]) : project_workflow_path(@project, @workflow)
    if @workflow.start!
      redirect_to fallback, notice: "Workflow started."
    else
      redirect_to fallback, alert: "Workflow has already been started."
    end
  end

  def resume
    if @workflow.resume!
      redirect_to project_workflow_path(@project, @workflow), notice: "Workflow resumed."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: "Workflow is not errored."
    end
  end

  # Manually sends a finished workflow back to the review stage so the next
  # scheduler tick re-inspects the PR and fixes outstanding findings/checks.
  def rollback_to_review
    if @workflow.rollback_to_review!
      redirect_to project_workflow_path(@project, @workflow), notice: "Workflow rolled back to review."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: "Only done workflows with a pull request can be rolled back."
    end
  end
end
