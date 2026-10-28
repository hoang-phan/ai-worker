class ProjectBrainstormsController < ApplicationController
  include ManualStartFlash
  include ProjectMemberScoped

  # Runs a brainstorm now instead of waiting for the hourly one. Like the scheduled run it only happens while
  # the project has no pending workflow; BrainstormJob imports the result as pending workflows.
  def create
    start_source_manually(
      Brainstorm::CycleSource.new(@project),
      label: "Brainstorm",
      started: "Agent is brainstorming workflows. They appear within the hour after it finishes.",
      already_running: "A brainstorm is already running for this project."
    )
  end
end
