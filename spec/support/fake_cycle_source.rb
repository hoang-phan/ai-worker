# Recording AgentRuns::CycleSource subclass for SyncCycle specs.
# Callers set failures / rescue_errors / eligible / etc. via accessors.
class FakeCycleSource < AgentRuns::CycleSource
  attr_accessor :calls, :payload, :eligible, :idle, :due, :blocker_list, :failures, :rescue_errors

  def initialize(calls)
    @calls = calls
    @eligible = @idle = @due = true
    @blocker_list = []
    @failures = {}
    @rescue_errors = [ ArgumentError, AiCli::CommandError ]
  end

  def poll = step(:poll) { payload }
  def import(p) = step(:import, p) { "result-of-#{p}" }
  def summary(r) = "summary(#{r})"
  def persist!(r, s) = step(:persist, r, s) { nil }
  def persist_failure!(m) = calls << [ :persist_failure, m ]
  def eligible? = eligible
  def idle? = idle
  def due? = due
  def blockers = blocker_list
  def start! = step(:start) { nil }
  def after_import(r) = calls << [ :after_import, r ]
  def after_start = calls << :after_start

  private

  def step(name, *args)
    calls << (args.empty? ? name : [ name, *args ])
    raise failures[name] if failures[name]

    yield
  end
end
