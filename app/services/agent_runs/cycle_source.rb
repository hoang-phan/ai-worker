# Base for the `source:` handed to AgentRuns::SyncCycle (and ManualStart.for).
# Subclasses must implement poll, import(payload), summary(result),
# persist!(result, summary), persist_failure!(message) and start!. The gates
# default to "yes", there are no blockers, and the hooks have defaults SyncCycle
# always calls: after_import and after_start do nothing, and log_detail(result)
# returns nil so the cycle logs "<log_prefix> <summary>". Override log_detail to
# append text after the summary (the cycle owns the prefix); it must return a
# String or nil. skip_reason returns a skip message for ManualStart (or nil);
# SyncCycle keeps using due? and does not call it. rescue_errors lists the
# errors SyncCycle / ManualStart record instead of raising; sources with their
# own FetchError override it with a RESCUE_ERRORS constant.
module AgentRuns
  class CycleSource
    def eligible? = true
    def idle? = true
    def due? = true
    def blockers = []
    def skip_reason = nil
    def rescue_errors = [ AiCli::CommandError ]
    def log_detail(_result) = nil
    def after_import(_result); end
    def after_start; end
  end
end
