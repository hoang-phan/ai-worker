class JiraSyncRunsController < ApplicationController
  include ManualStartFlash
  include ProjectScoped

  def create
    start_source_manually(
      Jira::SyncCycleSource.new(@project.jira_syncs.find(params[:id])),
      label: "Jira sync",
      started: "Asking the agent to fetch your Jira tickets. Workflows appear within a minute or two of it finishing.",
      already_running: "A Jira fetch is already running for this sync."
    )
  end
end
