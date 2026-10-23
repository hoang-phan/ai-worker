# Base for the `source:` handed to AgentRuns::SyncCycle. Subclasses must
# implement poll, import(payload), summary(result), persist!(result, summary),
# persist_failure!(message) and start!. The gates default to "yes", there are no
# blockers, and the hooks have defaults SyncCycle always calls: after_import and
# after_start do nothing, and log_message(result, summary) returns nil so the
# cycle logs "<log_prefix> <summary>". Override a hook to customise it;
# log_message must return a String (or nil for the default line).
module AgentRuns
  class CycleSource
    def eligible? = true
    def idle? = true
    def due? = true
    def blockers = []
    def log_message(_result, _summary) = nil
    def after_import(_result); end
    def after_start; end
  end
end
