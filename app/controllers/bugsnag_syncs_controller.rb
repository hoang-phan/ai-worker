class BugsnagSyncsController < ApplicationController
  include ProjectScoped

  before_action :set_bugsnag_sync, only: %i[edit update destroy]

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

  private

  def set_bugsnag_sync
    @bugsnag_sync = @project.bugsnag_syncs.find(params[:id])
  end

  def bugsnag_sync_params
    params.require(:bugsnag_sync).permit(:bugsnag_project, :jira_project, :min_events, :max_tickets, :auto_sync)
  end
end
