class BugsnagSyncRunsController < ApplicationController
  include ManualStartFlash
  include ProjectScoped

  def create
    @bugsnag_sync = @project.bugsnag_syncs.find(params[:id])
    sync = Bugsnag::TriageSync.new(@bugsnag_sync)
    result = AgentRuns::ManualStart.call(
      blockers: -> { sync.blockers },
      start: -> { sync.triager.start },
      rescue_errors: [ Bugsnag::FetchError, AiCli::CommandError ]
    )
    redirect_after_manual_start(
      result,
      to: @project,
      label: "Bugsnag sync",
      started: "Agent is triaging Bugsnag errors into Jira. The result shows here when it finishes.",
      already_running: "A Bugsnag triage is already running for this sync."
    )
  end
end
