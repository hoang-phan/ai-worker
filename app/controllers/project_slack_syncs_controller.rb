class ProjectSlackSyncsController < ApplicationController
  include ManualStartFlash
  include ProjectMemberScoped

  # Asks the agent to look for new Slack mentions with PRs right now instead of
  # waiting for the next 30-minute fetch; SlackReviewJob imports the result.
  def create
    start_source_manually(
      Slack::ReviewCycleSource.new(@project),
      label: "Slack sync",
      started: "Asking the agent to look through your Slack mentions. Review workflows appear within a minute or two of it finishing.",
      already_running: "A Slack fetch is already running for this project."
    )
  end
end
