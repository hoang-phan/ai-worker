# Adapts one Project's Brainstorm::Planner to AgentRuns::SyncCycle (driven by BrainstormJob).
# Owns SyncCycle gating: blockers, due/skip (pending workflows), and the last-run stamp.
# It only runs while the project has no pending workflow (`Workflow.queued`): proposals wait for you to Start them.
module Brainstorm
  class CycleSource < AgentRuns::CycleSource
    RESCUE_ERRORS = [ Brainstorm::FetchError, AiCli::CommandError ].freeze

    def initialize(project, planner: nil, clock: -> { Time.current })
      @project = project
      @planner = planner || Brainstorm::Planner.new(project)
      @clock = clock
    end

    def poll = @planner.poll
    def import(proposals) = @planner.import(proposals)
    def summary(result) = result.summary
    def persist!(_result, summary) = @project.update(brainstorm_last_result: summary)
    def persist_failure!(message) = @project.update(brainstorm_last_result: message)
    def idle? = !@planner.running?
    def due? = skip_reason.nil?
    def skip_reason
      queued = @project.workflows.queued.count
      "#{queued} workflow(s) still pending; start or delete them first." if queued.positive?
    end
    def blockers
      Projects::RunBlockers.new(@project).messages(:personal_kind, :brainstorm_goal, :local_directory)
    end
    def start! = @planner.start
    def after_start
      @project.update!(brainstorm_last_run_at: @clock.call)
    end
    def rescue_errors = RESCUE_ERRORS
  end
end
