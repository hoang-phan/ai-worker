class ProjectBrainstormsController < ApplicationController
  include ManualStartFlash
  include ProjectMemberScoped

  # Runs a brainstorm now instead of waiting for the hourly one. Like the scheduled run it only happens while
  # the project has no pending workflow; BrainstormJob imports the result as pending workflows.
  def create
    planner = Brainstorm::Planner.new(@project)
    start_manually(
      blockers: -> { planner.blockers },
      skip_reason: -> { planner.wait_reason },
      start: -> { planner.start },
      after_start: -> { planner.record_start! },
      rescue_errors: [ AiCli::CommandError ],
      label: "Brainstorm",
      started: "Agent is brainstorming workflows. They appear within the hour after it finishes.",
      already_running: "A brainstorm is already running for this project."
    )
  end
end
