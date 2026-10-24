# One pass of the detached-agent job sequence for a single record: poll a
# finished result, import it and record its summary, then start a new run only
# when the record is eligible, idle, due and unblocked. Expected errors are
# recorded and logged so later records in the calling job still run.
#
# The source is an AgentRuns::CycleSource subclass:
#   poll                        -> finished payload or nil
#   import(payload)             -> result
#   summary(result)             -> string
#   persist!(result, summary)   -> store the summary on the record
#   persist_failure!(message)   -> store "failed: ..." on the record
#   eligible? / idle? / due?    -> may start / nothing in flight / cadence allows
#   blockers                    -> array of reasons not to start
#   start!                      -> start the detached run
#   log_detail(result)          -> extra text appended to the info line
#                                  "<log_prefix> <summary>", or nil for none
#   after_import(result)        -> post-import hook (default no-op)
#   after_start                 -> hook run after a successful start (default no-op)
#   rescue_errors               -> errors recorded as failures instead of raised
#                                  (default [ AiCli::CommandError ]; the rescue_errors:
#                                  keyword overrides it)
module AgentRuns
  class SyncCycle
    Outcome = Struct.new(:imported, :started, :blocked, :failed, keyword_init: true) do
      def self.none = new(imported: false, started: false, blocked: false, failed: false)
    end

    def self.call(...) = new(...).call

    def initialize(source:, log_prefix:, rescue_errors: source.rescue_errors, logger: Rails.logger)
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
        @source.after_start
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
      line = "#{@log_prefix} #{summary}"
      detail = @source.log_detail(result)
      line = "#{line} #{detail}".strip if detail.present?
      @logger.info(line)
      @source.persist!(result, summary)
      @source.after_import(result)
    end
  end
end
