# Optional base for the `source:` handed to AgentRuns::SyncCycle. Subclasses
# must implement poll, import(payload), summary(result), persist!(result,
# summary), persist_failure!(message) and start!. The gates default to "yes",
# there are no blockers, and the hooks are optional (SyncCycle only calls
# log_message(result, summary), after_import(result) and after_start when the
# source responds to them).
module AgentRuns
  class CycleSource
    def eligible? = true
    def idle? = true
    def due? = true
    def blockers = []
    def after_import(_result); end
    def after_start; end
  end
end
