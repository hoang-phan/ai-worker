module Scheduling
  # Pure scheduling decisions for WorkflowSchedulerJob: which waiting workflows
  # may start, and what a clone is called. No queries, no side effects.
  module Planner
    module_function

    # Projects pointing at the same clone via different spellings ("~/x", "x/",
    # symlinks) must still count as one clone, or the per-clone guard misses them.
    def clone_key(project)
      path = File.expand_path(project.local_directory.to_s)
      File.exist?(path) ? File.realpath(path) : path
    end

    # An earlier (lower position) workflow that's merely waiting on review still
    # holds its project's slot, even if a later one is the one in flight.
    # Workflows on one project run strictly one after another: only the first
    # (by position) is eligible to start; later ones wait until it is done.
    # Runbook workflows are exempt like PR reviews, and start on a cron tick only when `auto_run`
    # is set; otherwise a person starts the stage with "Run stage" (`run_workflow_id`). Once it runs
    # it is polled like any other run, then moves on (`auto_advance`) or parks in `waiting` until Next.
    # PR-review workflows are the exception: they run once and never wait on
    # anyone, so they neither hold the slot nor are blocked by a development
    # workflow that is only waiting on its PR — only a *running* agent on the
    # same clone (Scheduling::Capacity) holds them back.
    #
    # `active_workflows` must be in `position` order; `waiting` keeps its order.
    def eligible_waiting(active_workflows:, waiting:, run_workflow_id: nil)
      heads = active_workflows.select(&:development?).uniq { |workflow| clone_key(workflow.project) }
      waiting.select do |workflow|
        if workflow.runbook? then workflow.id == run_workflow_id || workflow.auto_run?
        else workflow.pr_review? || heads.include?(workflow)
        end
      end
    end
  end
end
