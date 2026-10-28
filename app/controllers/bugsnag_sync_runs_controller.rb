class BugsnagSyncRunsController < ApplicationController
  include ManualStartFlash
  include ProjectScoped

  def create
    start_source_manually(
      Bugsnag::SyncCycleSource.new(@project.bugsnag_syncs.find(params[:id])),
      label: "Bugsnag sync",
      started: "Agent is triaging Bugsnag errors into Jira. The result shows here when it finishes.",
      already_running: "A Bugsnag triage is already running for this sync."
    )
  end
end
