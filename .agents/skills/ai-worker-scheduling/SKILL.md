---
name: ai-worker-scheduling
description: Applies ai-worker's scheduler discipline. Use for any task touching app/jobs/workflow_scheduler_job.rb, app/services/scheduling/**, config/sidekiq.yml, config/schedule.yml, or the scheduler concurrency specs (spec/jobs/workflow_scheduler_job_spec.rb, spec/services/scheduling/**).
---

# ai-worker-scheduling

Scope: `app/jobs/workflow_scheduler_job.rb`, `app/services/scheduling/planner.rb` (pure decisions: eligibility, `clone_key`), `app/services/scheduling/capacity.rb` (slot/clone bookkeeping), `app/services/scheduling/workflow_queries.rb` (the AR selection the job uses: status lists, ordering, due-UAT relation, free slots), `config/sidekiq.yml`, `config/schedule.yml`. What a started stage does is `StageExecutor` (`ai-worker-orchestration`, `ai-worker-stage-types`). The code wins over `docs/RUNBOOK.md`.

## Tick

`WorkflowSchedulerJob#perform(run_workflow_id = nil)` is cron-driven on the `stage_execution` queue (`schedule.yml`: every 3 minutes, in two entries for working hours 05–14 and off-hours, Asia/Ho_Chi_Minh). It walks every in-flight workflow in `position` order and never blocks on an agent. Three phases, in order:

1. **Active workflows** — `implementing`/`reviewing`/`local_testing`, plus `merged`/`uat_testing` ones that are `processing`. Running ones are executed (polled) first so finished runs free their slot and clone; then eligible waiting ones are started while `Capacity#can_start?` holds, calling `started!` only if the workflow is `processing` after `execute`.
2. **Post-merge** — skipped while any workflow is `implementing`/`local_testing` or any is `processing`. Otherwise `confirm_merges` runs `Stages::MergeCheck` for `done` development workflows with a PR URL that `tracks_jira_after_merge?`, then one non-processing `merged` workflow (lowest position) is executed.
3. **UAT** — free slots = `max_concurrent_agents` minus all `processing` workflows (no idle wait, no clone check). Due = `uat_waiting` with `uat_test_at` passed (moved to `uat_testing` first) or `uat_testing` and not processing (a failed attempt retried); ordered by `uat_test_at`, limited to the free slots.

`execute` rescues `StandardError` per workflow and logs `[scheduler]`, so one failure never stops the tick.

## Eligibility (`Planner.eligible_waiting`)

- Heads = the first (by position) *development* workflow in `active_workflows` per clone; a head waiting on review keeps its slot, so later development workflows on that clone don't start. `active_workflows` must be in `position` order.
- PR-review workflows are always eligible (they neither hold nor wait on the head); only a running agent on the same clone blocks them, via `Capacity`.
- Runbooks are eligible only if `auto_run?` or `id == run_workflow_id` (the "Run stage" button); they never become heads.

## Capacity and clone key

- `Capacity.new(busy_clones:, max:)`: can start iff `active_count < max` and the workflow's `clone_key` isn't busy. `busy_clones` is built from all `processing` workflows (all statuses, so a running `merged`/UAT run counts) and the initial list is copied, not mutated. `max` is `WorkflowSchedulerJob.max_concurrent_agents` (`MAX_CONCURRENT_AGENTS`, default 3).
- `Planner.clone_key(project)` = `realpath` of the expanded `local_directory` if it exists, else the expanded path. Always go through it; never compare raw `local_directory` strings.

## Concurrency-1 contract

Capacity and head-of-line checks aren't atomic, so ticks must serialize: `config/sidekiq.yml` keeps `:concurrency: 1` (production runs a dedicated `-c 1 -q stage_execution` process, see `docs/RUNBOOK.md`). Parallelism comes from detached agent processes. Don't relax one rule (per-clone, global max, development one-at-a-time) without revisiting the others, and don't move the scheduler off the `stage_execution` queue.

## Specs

| Rule | Spec |
|---|---|
| Poll running before starting waiting | `workflow_scheduler_job_spec.rb` "polls processing workflows before starting…" |
| One start per shared clone | `workflow_scheduler_job_spec.rb` "starts only one waiting workflow for a shared clone" |
| Global max | `workflow_scheduler_job_spec.rb` "with one agent slot" |
| Per-workflow failure isolation | `workflow_scheduler_job_spec.rb` "logs one executor failure and continues…" |
| Post-merge idle gate, confirm + start one | `workflow_scheduler_job_spec.rb` "the post-merge phase" |
| UAT due/retry and slot limit | `workflow_scheduler_job_spec.rb` "the UAT phase" |
| Named non-auto-run runbook | `workflow_scheduler_job_spec.rb` "starts a named non-auto-run runbook" |
| Head-of-line, PR-review exemption, runbook rules | `spec/services/scheduling/planner_spec.rb` `.eligible_waiting` |
| Clone-key normalisation | `spec/services/scheduling/planner_spec.rb` `.clone_key` |
| Slot/clone bookkeeping | `spec/services/scheduling/capacity_spec.rb` |

Run with `RAILS_ENV=test bundle exec rspec spec/jobs/workflow_scheduler_job_spec.rb spec/services/scheduling`. A new rule goes in the pure `Planner`/`Capacity` first (with a spec there) and gets a job-level spec only for phase wiring.
