module Jira
  # `reason` is a machine-readable code (e.g. :missing_credentials); nil for ordinary Jira/transport failures.
  class WorklogError < StandardError
    attr_reader :reason

    def initialize(message = nil, reason: nil)
      super(message)
      @reason = reason
    end

    def missing_credentials?
      reason == :missing_credentials
    end
  end
end
