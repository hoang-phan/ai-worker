# Runs hourly. For each personal project with brainstorming on: imports a finished agent run as pending
# workflows, then starts a new one only when the project has no pending workflow (see Workflow.queued). The agent runs detached; this job never waits on it.
class BrainstormJob < ApplicationJob
  queue_as :default

  def perform(source_factory: Brainstorm::CycleSource.method(:new), cycle: AgentRuns::SyncCycle,
              logger: Rails.logger)
    Project.personal.where(brainstorm_enabled: true).find_each do |project|
      cycle.call(
        source: source_factory.call(project),
        log_prefix: "[BrainstormJob] project=#{project.id}",
        logger: logger
      )
    end
  end
end
