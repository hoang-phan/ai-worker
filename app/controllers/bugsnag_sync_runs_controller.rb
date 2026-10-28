class BugsnagSyncRunsController < ApplicationController
  include ManualStartFlash
  include ProjectScoped

  def create
    source = Bugsnag::SyncCycleSource.new(@project.bugsnag_syncs.find(params[:id]))
    result = AgentRuns::ManualStart.for(source).call
    redirect_after_manual_start(
      result,
      to: @project,
      label: "Bugsnag sync",
      started: "Agent is triaging Bugsnag errors into Jira. The result shows here when it finishes.",
      already_running: "A Bugsnag triage is already running for this sync."
    )
  end
end
