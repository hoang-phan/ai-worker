# One pass of the detached-agent job sequence for a single record: poll a
# finished result, import it and record its summary, then start a new run only
# when the record is eligible, idle, due and unblocked. Expected errors are
# recorded and logged so later records in the calling job still run.
#
# The source is a duck-typed object (see AgentRuns::CycleSource):
#   poll                        -> finished payload or nil
#   import(payload)             -> result
#   summary(result)             -> string
#   persist!(result, summary)   -> store the summary on the record
#   persist_failure!(message)   -> store "failed: ..." on the record
#   eligible? / idle? / due?    -> may start / nothing in flight / cadence allows
#   blockers                    -> array of reasons not to start
#   start!                      -> start the detached run
#   log_message(result, summary) (optional) -> info line body; defaults to "<log_prefix> <summary>"
#   after_import(result)        (optional) -> post-import hook
#   after_start                 (optional) -> hook run after a successful start
module AgentRuns
  class SyncCycle
    Outcome = Struct.new(:imported, :started, :blocked, :failed, keyword_init: true) do
      def self.none = new(imported: false, started: false, blocked: false, failed: false)
    end

    def self.call(...) = new(...).call

    def initialize(source:, log_prefix:, rescue_errors:, logger: Rails.logger)
      @source = source
      @log_prefix = log_prefix
      @rescue_errors = rescue_errors
      @logger = logger
    end

    def call
      outcome = Outcome.none
      payload = @source.poll
      if payload
        record(@source.import(payload))
        outcome.imported = true
      end

      return outcome unless @source.eligible? && @source.idle? && @source.due?

      reasons = @source.blockers
      if reasons.any?
        @logger.warn("#{@log_prefix} blocked: #{reasons.join('; ')}")
        outcome.blocked = true
      else
        @source.start!
        @source.after_start if @source.respond_to?(:after_start)
        outcome.started = true
      end
      outcome
    rescue *@rescue_errors => e
      @logger.error("#{@log_prefix} #{e.message}")
      @source.persist_failure!("failed: #{e.message}".truncate(250))
      Outcome.new(imported: outcome.imported, started: false, blocked: false, failed: true)
    end

    private

    def record(result)
      summary = @source.summary(result)
      @logger.info(log_message(result, summary))
      @source.persist!(result, summary)
      @source.after_import(result) if @source.respond_to?(:after_import)
    end

    def log_message(result, summary)
      return "#{@log_prefix} #{summary}" unless @source.respond_to?(:log_message)

      @source.log_message(result, summary)
    end
  end
end
