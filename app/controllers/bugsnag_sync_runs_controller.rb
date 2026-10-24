class BugsnagSyncRunsController < ApplicationController
  include ManualStartFlash
  include ProjectScoped

  def create
    @bugsnag_sync = @project.bugsnag_syncs.find(params[:id])
    sync = Bugsnag::TriageSync.new(@bugsnag_sync)
    start_manually(
      blockers: -> { sync.blockers },
      start: -> { sync.triager.start },
      rescue_errors: Bugsnag::SyncCycleSource::RESCUE_ERRORS,
      label: "Bugsnag sync",
      started: "Agent is triaging Bugsnag errors into Jira. The result shows here when it finishes.",
      already_running: "A Bugsnag triage is already running for this sync."
    )
  end
end
