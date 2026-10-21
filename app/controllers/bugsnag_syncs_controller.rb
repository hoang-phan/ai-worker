class BugsnagSyncsController < ApplicationController
  before_action :set_project
  before_action :set_bugsnag_sync, only: %i[edit update destroy run]

  def new
    @bugsnag_sync = @project.bugsnag_syncs.new
  end

  def edit
  end

  def create
    @bugsnag_sync = @project.bugsnag_syncs.new(bugsnag_sync_params)
    if @bugsnag_sync.save
      redirect_to @project, notice: "Bugsnag sync created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @bugsnag_sync.update(bugsnag_sync_params)
      redirect_to @project, notice: "Bugsnag sync updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @bugsnag_sync.destroy
    redirect_to @project, notice: "Bugsnag sync deleted."
  end

  def run
    triager = Bugsnag::Triager.new(@bugsnag_sync)
    result = AgentRuns::ManualStart.call(
      blockers: -> { triager.blockers },
      start: -> { triager.start },
      rescue_errors: [ Bugsnag::FetchError, AiCli::CommandError ]
    )
    case result.status
    when :blocked
      redirect_to @project, alert: "Bugsnag sync blocked: #{result.detail}"
    when :started
      redirect_to @project, notice: "Agent is triaging Bugsnag errors into Jira. The result shows here when it finishes."
    when :already_running
      redirect_to @project, alert: "A Bugsnag triage is already running for this sync."
    when :failed
      redirect_to @project, alert: "Bugsnag sync failed: #{result.detail}"
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_bugsnag_sync
    @bugsnag_sync = @project.bugsnag_syncs.find(params[:id])
  end

  def bugsnag_sync_params
    params.require(:bugsnag_sync).permit(:bugsnag_project, :jira_project, :min_events, :max_tickets, :auto_sync)
  end
end
