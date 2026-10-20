# One pass of the detached-agent job sequence for a single record: poll a
# finished result, import it and record its summary, then start a new run only
# when the record is eligible, idle, due and unblocked. Expected errors are
# recorded and logged so later records in the calling job still run.
#
# Callbacks (all callables):
#   poll         -> finished payload or nil
#   import       -> (payload) result
#   summary      -> (result) string
#   persist      -> (result, summary) store the summary on the record
#   log_message  -> (result, summary) info line body; defaults to the summary
#   after_import -> (result) post-import hook
#   eligible     -> whether this record may start runs at all
#   idle         -> whether no run is in flight
#   due          -> whether the cadence allows a new run
#   blockers     -> array of reasons not to start
#   start        -> start the detached run
#   after_start  -> hook run after a successful start
#   persist_failure -> (message) store "failed: ..." on the record
module AgentRuns
  class SyncCycle
    Outcome = Struct.new(:imported, :started, :blocked, :failed, keyword_init: true) do
      def self.none = new(imported: false, started: false, blocked: false, failed: false)
    end

    def self.call(...) = new(...).call

    def initialize(log_prefix:, rescue_errors:, poll:, import:, summary:, persist:, persist_failure:, start:,
                   blockers: -> { [] }, eligible: -> { true }, idle: -> { true }, due: -> { true },
                   log_message: nil, after_import: nil, after_start: nil, logger: Rails.logger)
      @log_prefix = log_prefix
      @rescue_errors = rescue_errors
      @poll = poll
      @import = import
      @summary = summary
      @persist = persist
      @persist_failure = persist_failure
      @start = start
      @blockers = blockers
      @eligible = eligible
      @idle = idle
      @due = due
      @log_message = log_message
      @after_import = after_import
      @after_start = after_start
      @logger = logger
    end

    def call
      outcome = Outcome.none
      payload = @poll.call
      if payload
        record(@import.call(payload))
        outcome.imported = true
      end

      return outcome unless @eligible.call && @idle.call && @due.call

      reasons = @blockers.call
      if reasons.any?
        @logger.warn("#{@log_prefix} blocked: #{reasons.join('; ')}")
        outcome.blocked = true
      else
        @start.call
        @after_start&.call
        outcome.started = true
      end
      outcome
    rescue *@rescue_errors => e
      @logger.error("#{@log_prefix} #{e.message}")
      @persist_failure.call("failed: #{e.message}".truncate(250))
      Outcome.new(imported: outcome.imported, started: false, blocked: false, failed: true)
    end

    private

    def record(result)
      summary = @summary.call(result)
      @logger.info(@log_message ? @log_message.call(result, summary) : "#{@log_prefix} #{summary}")
      @persist.call(result, summary)
      @after_import&.call(result)
    end
  end
end
