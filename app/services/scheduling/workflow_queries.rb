module Scheduling
  # The ActiveRecord selection behind WorkflowSchedulerJob ticks. Scheduling::Planner stays
  # query-free; the job orchestrates; this module owns "which rows".
  module WorkflowQueries
    module_function

    # In-flight workflows that are started (or waiting to be) by the cron tick. `reviewing` is
    # included so a head workflow waiting on review keeps its clone slot (see Planner).
    ACTIVE_STATUSES = %i[implementing reviewing local_testing ci_checking ci_verifying opening_pr].freeze

    # Statuses that are only "in flight" while an agent run is processing: a Jira update after
    # merge (`merged`) or a UAT browser test (`uat_testing`). Mid-run they're polled like any other run.
    POLLING_STATUSES = %i[merged uat_testing].freeze

    def active
      Workflow.where(status: ACTIVE_STATUSES).includes(:project).order(:position).to_a
    end

    def polling_updates
      Workflow.where(status: POLLING_STATUSES, processing: true).includes(:project).order(:position).to_a
    end

    def busy_clone_keys
      Workflow.where(processing: true).includes(:project).map { |workflow| Planner.clone_key(workflow.project) }
    end

    # Status is deliberately ignored: the active runner has already started whatever it could this
    # tick, so a workflow that is merely queued (e.g. `implementing` behind a head waiting on review)
    # must not keep merged PRs from getting their Jira update.
    def work_in_progress?
      Workflow.where(processing: true).exists?
    end

    # Done development workflows whose PR may have been merged.
    def merge_candidates
      Workflow.done.development.where.not(github_pr_url: nil).includes(:project).order(:position)
    end

    # Next `merged` workflow not already running (a running one is polled by the active phase).
    def next_merged
      Workflow.merged.where(processing: false).includes(:project).order(:position).first
    end

    def free_agent_slots(max:)
      max - Workflow.where(processing: true).count
    end

    # `uat_waiting` once its delay has passed, or `uat_testing` but idle (a failed attempt being retried).
    def due_uat_tests(limit:, now:)
      due = Workflow.where(status: :uat_waiting).where(uat_test_at: ..now)
                    .or(Workflow.where(status: :uat_testing, processing: false))
      due.includes(:project).order(:uat_test_at).limit(limit)
    end
  end
end
