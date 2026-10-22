# Runs hourly. For each personal project with brainstorming on: imports a finished agent run as pending
# workflows, then starts a new one only when the project has no pending workflow (see Workflow.queued). The agent runs detached; this job never waits on it.
class BrainstormJob < ApplicationJob
  queue_as :default

  def perform
    Project.personal.where(brainstorm_enabled: true).find_each do |project|
      AgentRuns::SyncCycle.call(
        source: Brainstorm::CycleSource.new(project),
        log_prefix: "[BrainstormJob] project=#{project.id}",
        rescue_errors: [ Brainstorm::FetchError, AiCli::CommandError ]
      )
    end
  end
end
