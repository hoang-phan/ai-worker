class WorkflowRunbooksController < ApplicationController
  include ProjectScoped
  include WorkflowScoped

  before_action :set_workflow

  # The runbook's "Run stage" button: starts the current stage (also retries a failed one) and lets the
  # scheduler carry on through the following stages until one needs a person.
  def run_stage
    if @workflow.request_stage_run!
      WorkflowSchedulerJob.perform_later(@workflow.id)
      redirect_to project_workflow_path(@project, @workflow), notice: "Running stage."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: "Workflow has no stage ready to run."
    end
  end

  # The runbook's Next button: only valid while a finished stage is waiting for it.
  def advance
    if @workflow.can_advance?
      @workflow.advance!
      WorkflowSchedulerJob.perform_later(@workflow.id) if @workflow.auto_run?
      redirect_to project_workflow_path(@project, @workflow), notice: @workflow.done? ? "Runbook finished." : "Moved on to the next stage."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: "Workflow is not waiting for Next."
    end
  end

  # The runbook's Clone button: a fresh pending runbook (see Workflows::RunbookClone), opened for editing.
  def clone
    result = Workflows::RunbookClone.new(@workflow).call
    case result.status
    when :not_runbook
      redirect_to project_workflow_path(@project, @workflow), alert: "Only runbooks can be cloned."
    when :created
      redirect_to edit_project_workflow_path(@project, result.copy), notice: "Cloned with #{result.copy.stages.count} stages. Check the variables, then Start."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: result.error
    end
  end
end
