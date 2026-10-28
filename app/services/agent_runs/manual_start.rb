# The "run now" button flow shared by the manual sync/brainstorm actions: refuse
# when blocked, optionally skip, try to start, and report why nothing started.
# Controllers map the status to their own flash wording via ManualStartFlash.
#
# Prefer ManualStart.for(source) when the record has an AgentRuns::CycleSource:
# that wires blockers / skip_reason / start! / after_start / rescue_errors from
# the source so the source stays the single place that knows how the run is
# gated, started and rescued.
#
# Callbacks (all callables):
#   blockers    -> array of reasons not to start
#   skip_reason -> message when the run should be skipped, else nil
#   start       -> true when a run began, false when one is already running
#   after_start -> hook run only after a successful start
#
# Statuses: :blocked (detail: blockers joined with "; "), :skipped (detail: the
# skip message), :started, :already_running, :failed (detail: error message).
module AgentRuns
  class ManualStart
    Result = Struct.new(:status, :detail, keyword_init: true)

    def self.for(source)
      new(
        blockers: source.method(:blockers),
        skip_reason: source.method(:skip_reason),
        start: source.method(:start!),
        after_start: source.method(:after_start),
        rescue_errors: source.rescue_errors
      )
    end

    def initialize(blockers:, start:, rescue_errors:, skip_reason: -> { nil }, after_start: nil)
      @blockers = blockers
      @skip_reason = skip_reason
      @start = start
      @after_start = after_start
      @rescue_errors = rescue_errors
    end

    def call
      reasons = @blockers.call
      return Result.new(status: :blocked, detail: reasons.join("; ")) if reasons.any?

      skip = @skip_reason.call
      return Result.new(status: :skipped, detail: skip) if skip

      return Result.new(status: :already_running) unless @start.call

      @after_start&.call
      Result.new(status: :started)
    rescue *@rescue_errors => e
      Result.new(status: :failed, detail: e.message)
    end
  end
end
