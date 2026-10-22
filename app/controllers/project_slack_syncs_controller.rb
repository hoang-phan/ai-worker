class ProjectSlackSyncsController < ApplicationController
  include ManualStartFlash

  before_action :set_project

  # Asks the agent to look for new Slack mentions with PRs right now instead of
  # waiting for the next 30-minute fetch; SlackReviewJob imports the result.
  def create
    sync = Slack::ReviewSync.new(@project)
    result = AgentRuns::ManualStart.call(
      blockers: -> { sync.blockers },
      start: -> { sync.fetcher.start },
      rescue_errors: [ AiCli::CommandError ]
    )
    redirect_after_manual_start(
      result,
      to: @project,
      label: "Slack sync",
      started: "Asking the agent to look through your Slack mentions. Review workflows appear within a minute or two of it finishing.",
      already_running: "A Slack fetch is already running for this project."
    )
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end
end
