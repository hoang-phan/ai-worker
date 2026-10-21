class JiraSyncsController < ApplicationController
  include ManualStartFlash

  before_action :set_project
  before_action :set_jira_sync, only: %i[edit update destroy run]

  def new
    @jira_sync = @project.jira_syncs.new
  end

  def edit
  end

  def create
    @jira_sync = @project.jira_syncs.new(jira_sync_params)
    if @jira_sync.save
      redirect_to @project, notice: "Jira sync created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @jira_sync.update(jira_sync_params)
      redirect_to @project, notice: "Jira sync updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @jira_sync.destroy
    redirect_to @project, notice: "Jira sync deleted."
  end

  def run
    sync = Jira::TicketSync.new(@jira_sync)
    result = AgentRuns::ManualStart.call(
      blockers: -> { sync.blockers },
      start: -> { sync.fetcher.start },
      rescue_errors: [ Jira::FetchError, AiCli::CommandError ]
    )
    redirect_after_manual_start(
      result,
      to: @project,
      label: "Jira sync",
      started: "Asking the agent to fetch your Jira tickets. Workflows appear within a minute or two of it finishing.",
      already_running: "A Jira fetch is already running for this sync."
    )
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_jira_sync
    @jira_sync = @project.jira_syncs.find(params[:id])
  end

  def jira_sync_params
    params.require(:jira_sync).permit(:jira_project, :parent_ticket, :auto_sync)
  end
end
