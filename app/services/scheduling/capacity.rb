module Scheduling
  # Tracks running agents: at most `max` overall and one per local clone.
  # Stages `git checkout`/`pull`/`merge` in `project.local_directory`, which would
  # corrupt a run in progress on the same clone.
  class Capacity
    # Max agent CLI runs (`claude -p` / `agent -p`) in flight at once, across all projects.
    def self.default_max(env: ENV)
      env.fetch("MAX_CONCURRENT_AGENTS", 3).to_i
    end

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
