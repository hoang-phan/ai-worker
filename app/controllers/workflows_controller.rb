class WorkflowsController < ApplicationController
  before_action :set_project
  before_action :set_workflow, only: %i[show edit update destroy start run_stage clone move advance resume rollback_to_review destroy_image]

  def show
    @stage_runs = @workflow.stages.flat_map(&:stage_runs).sort_by(&:created_at).reverse
  end

  def new
    @workflow = @project.workflows.new(position: @project.next_workflow_position, skills: @project.default_skills, github_reviewer: @project.default_reviewers,
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

  # Batch "Log time" buttons (project page) and the single-workflow buttons (workflow page): each selected
  # workflow gets one worklog of `hours`, placed on the next available weekday (see Jira::TimeSlotPlanner).
  def log_time
    hours = params[:hours].to_f
    return redirect_back_or_to(@project, alert: "Pick one of #{Jira::TimeLogger::PRESET_HOURS.join(', ')} hours.") unless Jira::TimeLogger::PRESET_HOURS.include?(hours)

    workflows = @project.workflows.where(id: Array(params[:workflow_ids])).order(:position, :id)
    return redirect_back_or_to(@project, alert: "Select at least one workflow.") if workflows.empty?

    result = Jira::TimeLogBatch.new.call(workflows, hours)
    redirect_back_or_to @project, (result.success? ? :notice : :alert) => result.message(hours)
  end

  def destroy_image
    @workflow.remove_image(params[:name])
    redirect_back_or_to edit_project_workflow_path(@project, @workflow), notice: "Image removed."
  end

  def start
    if @workflow.start!
      redirect_back_or_to project_workflow_path(@project, @workflow), notice: "Workflow started."
    else
      redirect_back_or_to project_workflow_path(@project, @workflow), alert: "Workflow has already been started."
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

  # Up/down arrows on the project page: reorders the priority list (the scheduler works through workflows by position).
  def move
    direction = params[:direction].to_s
    return redirect_to @project, alert: "Unknown direction." unless %w[up down].include?(direction)

    Projects::WorkflowReorder.new(@project).move(@workflow, direction)
    redirect_to @project
  end

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

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_workflow
    @workflow = @project.workflows.find(params[:id])
  end

  def workflow_params
    params.require(:workflow).permit(:jira_ticket, :branch_name, :github_reviewer, :skills, :task_description, :position, :variables_text, :copy_stages_from_id, :slack_review_thread_ts)
  end
end
