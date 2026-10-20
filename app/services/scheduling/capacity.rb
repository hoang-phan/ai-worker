module Scheduling
  # Tracks running agents: at most `max` overall and one per local clone.
  # Stages `git checkout`/`pull`/`merge` in `project.local_directory`, which would
  # corrupt a run in progress on the same clone.
  class Capacity
    def initialize(busy_clones:, max:)
      @busy_clones = busy_clones.to_a.dup
      @max = max
    end

    def active_count
      @busy_clones.size
    end

    def can_start?(workflow)
      active_count < @max && !@busy_clones.include?(Planner.clone_key(workflow.project))
    end

    def started!(workflow)
      @busy_clones << Planner.clone_key(workflow.project)
    end
  end
end
