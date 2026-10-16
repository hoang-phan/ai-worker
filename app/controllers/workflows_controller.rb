class WorkflowsController < ApplicationController
  before_action :set_project
  before_action :set_workflow, only: %i[show edit update destroy start run_stage clone advance resume rollback_to_review destroy_image]

  def show
    @stage_runs = @workflow.stages.flat_map(&:stage_runs).sort_by(&:created_at).reverse
  end

  def new
    @workflow = @project.workflows.new(position: next_position, skills: @project.default_skills, github_reviewer: @project.default_reviewers,
                                       kind: params[:kind] == "runbook" ? :runbook : :development)
  end

  def edit
  end

  def create
    @workflow = @project.workflows.new(workflow_params)
    @workflow.kind = params.dig(:workflow, :kind) == "runbook" ? :runbook : :development
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
      @workflow.runbook? ? @workflow.start_runbook! : @workflow.update!(status: :implementing)
      redirect_back_or_to project_workflow_path(@project, @workflow), notice: "Workflow started."
    else
      redirect_back_or_to project_workflow_path(@project, @workflow), alert: "Workflow has already been started."
    end
  end

  # The runbook's Clone button: a fresh pending runbook with the same stages and the variables the user
  # set up front (channel etc.). Variables a stage emitted (version, work list, tag …) are dropped so
  # last run's results can't leak into this one. Opened for editing.
  def clone
    unless @workflow.runbook?
      return redirect_to project_workflow_path(@project, @workflow), alert: "Only runbooks can be cloned."
    end

    copy = @project.workflows.new(kind: :runbook, position: next_position, copy_stages_from_id: @workflow.id,
                                  variables: @workflow.input_variables)
    if copy.save
      redirect_to edit_project_workflow_path(@project, copy), notice: "Cloned with #{copy.stages.count} stages. Check the variables, then Start."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: copy.errors.full_messages.to_sentence
    end
  end

  # The runbook's "Run stage" button: starts the current stage (also retries a failed one) and lets the
  # scheduler carry on through the following stages until one needs a person.
  def run_stage
    if @workflow.runbook? && @workflow.implementing? && !@workflow.processing?
      @workflow.update!(auto_run: true)
      WorkflowSchedulerJob.perform_later(@workflow.id)
      redirect_to project_workflow_path(@project, @workflow), notice: "Running stage."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: "Workflow has no stage ready to run."
    end
  end

  # The runbook's Next button: only valid while a finished stage is waiting for it.
  def advance
    if @workflow.runbook? && @workflow.awaiting_next?
      @workflow.advance!
      WorkflowSchedulerJob.perform_later(@workflow.id) if @workflow.auto_run?
      redirect_to project_workflow_path(@project, @workflow), notice: @workflow.done? ? "Runbook finished." : "Moved on to the next stage."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: "Workflow is not waiting for Next."
    end
  end

  def resume
    if @workflow.errored?
      @workflow.update!(status: @workflow.resume_status)
      @workflow.current_stage&.stage_runs&.create!(action: "resumed")
      redirect_to project_workflow_path(@project, @workflow), notice: "Workflow resumed."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: "Workflow is not errored."
    end
  end

  # Manually sends a finished workflow back to the review stage so the next
  # scheduler tick re-inspects the PR and fixes outstanding findings/checks.
  def rollback_to_review
    if @workflow.done? && @workflow.development? && @workflow.github_pr_url.present?
      @workflow.update!(status: :reviewing)
      @workflow.current_stage&.stage_runs&.create!(action: "rolled_back_to_review")
      redirect_to project_workflow_path(@project, @workflow), notice: "Workflow rolled back to review."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: "Only done workflows with a pull request can be rolled back."
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
    params.require(:workflow).permit(:jira_ticket, :branch_name, :github_reviewer, :skills, :task_description, :position, :variables_text, :copy_stages_from_id)
  end
end
