class JiraSyncRunsController < ApplicationController
  include ManualStartFlash
  include ProjectScoped

  def create
    @jira_sync = @project.jira_syncs.find(params[:id])
    sync = Jira::TicketSync.new(@jira_sync)
    start_manually(
      blockers: -> { sync.blockers },
      start: -> { sync.fetcher.start },
      rescue_errors: [ Jira::FetchError, AiCli::CommandError ],
      label: "Jira sync",
      started: "Asking the agent to fetch your Jira tickets. Workflows appear within a minute or two of it finishing.",
      already_running: "A Jira fetch is already running for this sync."
    )
  end
end
