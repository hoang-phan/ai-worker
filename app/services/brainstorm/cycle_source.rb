# Adapts one Project's Brainstorm::Planner to AgentRuns::SyncCycle (driven by BrainstormJob).
module Brainstorm
  class CycleSource < AgentRuns::CycleSource
    RESCUE_ERRORS = [ Brainstorm::FetchError, AiCli::CommandError ].freeze

    def initialize(project, planner: nil)
      @project = project
      @planner = planner || Brainstorm::Planner.new(project)
    end

    def poll = @planner.poll
    def import(proposals) = @planner.import(proposals)
    def summary(result) = result.summary
    def persist!(_result, summary) = @project.update(brainstorm_last_result: summary)
    def persist_failure!(message) = @project.update(brainstorm_last_result: message)
    def idle? = !@planner.running?
    def due? = @planner.wait_reason.nil?
    def skip_reason = @planner.wait_reason
    def blockers = @planner.blockers
    def start! = @planner.start
    def after_start = @planner.record_start!
    def rescue_errors = RESCUE_ERRORS
  end
end
