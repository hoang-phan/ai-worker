module Github
  # Decides whether a PR's statusCheckRollup contains a finished, failing check.
  # Checks still queued/in progress (no conclusion yet) are ignored.
  class FailingChecks
    FAILED_CONCLUSIONS = %w[FAILURE TIMED_OUT STARTUP_FAILURE ACTION_REQUIRED].freeze
    FAILED_STATES = %w[FAILURE ERROR].freeze

    def self.call(rollup)
      rollup.any? do |check|
        FAILED_CONCLUSIONS.include?(check["conclusion"].to_s.upcase) ||
          FAILED_STATES.include?(check["state"].to_s.upcase)
      end
    end
  end
end
