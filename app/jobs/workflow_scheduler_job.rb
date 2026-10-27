class WorkflowSchedulerJob < ApplicationJob
  queue_as :stage_execution

  def self.max_concurrent_agents = Scheduling::Capacity.default_max

  def perform(run_workflow_id = nil, tick: nil)
    (tick || Scheduling::Tick.new(max_capacity: self.class.max_concurrent_agents)).call(run_workflow_id)
  end
end
