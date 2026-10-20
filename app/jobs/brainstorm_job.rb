# Runs hourly. For each personal project with brainstorming on: imports a finished agent run as pending
# workflows, then starts a new one only when the project has no pending workflow (see Workflow.queued). The agent runs detached; this job never waits on it.
class BrainstormJob < ApplicationJob
  queue_as :default

  def perform
    Project.personal.where(brainstorm_enabled: true).find_each do |project|
      planner = Brainstorm::Planner.new(project)

      AgentRuns::SyncCycle.call(
        log_prefix: "[BrainstormJob] project=#{project.id}",
        rescue_errors: [ Brainstorm::FetchError, AiCli::CommandError ],
        poll: -> { planner.poll },
        import: ->(proposals) { planner.import(proposals) },
        summary: ->(result) { "created #{result.created.size}, skipped #{result.skipped.size}" },
        persist: ->(_result, summary) { project.update(brainstorm_last_result: summary) },
        idle: -> { !planner.running? },
        due: -> { planner.queued_count.zero? },
        blockers: -> { planner.blockers },
        start: -> { planner.start },
        after_start: -> { project.update(brainstorm_last_run_at: Time.current) },
        persist_failure: ->(message) { project.update(brainstorm_last_result: message) }
      )
    end
  end
end
