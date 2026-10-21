# The "run now" button flow shared by the manual sync/brainstorm actions: refuse
# when blocked, optionally skip, try to start, and report why nothing started.
# Controllers map the status to their own flash wording.
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

    def self.call(...) = new(...).call

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
