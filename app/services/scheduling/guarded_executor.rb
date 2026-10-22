module Scheduling
  # Runs the executor for one workflow; a StandardError is logged and swallowed so one workflow's
  # failure never stops the rest of the tick.
  class GuardedExecutor
    def initialize(executor:, logger:)
      @executor = executor
      @logger = logger
    end

    def call(workflow)
      @executor.call(workflow)
    rescue StandardError => e
      @logger.error("[scheduler] workflow=#{workflow.id} #{e.class}: #{e.message}")
    end
  end
end
