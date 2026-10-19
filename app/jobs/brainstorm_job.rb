# Runs hourly. For each personal project with brainstorming on: imports a finished agent run as pending
# workflows, then starts a new one only when the project has no pending workflow (see Workflow.queued). The agent runs detached; this job never waits on it.
class BrainstormJob < ApplicationJob
  queue_as :default

  def perform
    Project.personal.where(brainstorm_enabled: true).find_each do |project|
      planner = Brainstorm::Planner.new(project)

      proposals = planner.poll
      record(project, planner.import(proposals)) if proposals

      next if planner.running? || planner.queued_count.positive?

      blockers = planner.blockers
      if blockers.any?
        Rails.logger.warn("[BrainstormJob] project=#{project.id} blocked: #{blockers.join('; ')}")
      else
        planner.start
        project.update(brainstorm_last_run_at: Time.current)
      end
    rescue Brainstorm::FetchError, AiCli::CommandError => e
      Rails.logger.error("[BrainstormJob] project=#{project.id} #{e.message}")
      project.update(brainstorm_last_result: "failed: #{e.message}".truncate(250))
    end
  end

  private

  def record(project, result)
    summary = "created #{result.created.size}, skipped #{result.skipped.size}"
    Rails.logger.info("[BrainstormJob] project=#{project.id} #{summary}")
    project.update(brainstorm_last_result: summary)
  end
end
