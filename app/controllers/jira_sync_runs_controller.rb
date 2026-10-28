class JiraSyncRunsController < ApplicationController
  include ManualStartFlash
  include ProjectScoped

  def create
    source = Jira::SyncCycleSource.new(@project.jira_syncs.find(params[:id]))
    result = AgentRuns::ManualStart.for(source).call
    redirect_after_manual_start(
      result,
      to: @project,
      label: "Jira sync",
      started: "Asking the agent to fetch your Jira tickets. Workflows appear within a minute or two of it finishing.",
      already_running: "A Jira fetch is already running for this sync."
    )
  end
end
