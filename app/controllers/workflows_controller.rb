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

    logger = Jira::TimeLogger.new
    logged = []
    failure = nil
    workflows.each do |workflow|
      logged << logger.log(workflow, hours)
    rescue Jira::WorklogError => e
      failure = e.message
      break
    end

    summary = logged.map { |log| "#{log.ticket_key} #{l(log.started_at, format: :short)}" }.to_sentence
    if failure
      message = "#{failure}.#{" Logged before that: #{summary}." if logged.any?}"
      redirect_back_or_to @project, alert: message
    else
      redirect_back_or_to @project, notice: "Logged #{hours} h on #{summary}."
    end
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

  # The runbook's Clone button: a fresh pending runbook with the same stages and the variables the user
  # set up front (channel etc.). Variables a stage emitted (version, work list, tag …) are dropped so
  # last run's results can't leak into this one. Opened for editing.
  def clone
    unless @workflow.runbook?
      return redirect_to project_workflow_path(@project, @workflow), alert: "Only runbooks can be cloned."
    end

    copy = @project.workflows.new(kind: :runbook, position: @project.next_workflow_position, copy_stages_from_id: @workflow.id,
                                  variables: @workflow.input_variables)
    if copy.save
      redirect_to edit_project_workflow_path(@project, copy), notice: "Cloned with #{copy.stages.count} stages. Check the variables, then Start."
    else
      redirect_to project_workflow_path(@project, @workflow), alert: copy.errors.full_messages.to_sentence
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
