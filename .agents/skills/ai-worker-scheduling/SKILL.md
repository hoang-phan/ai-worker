---
name: ai-worker-scheduling
description: Applies ai-worker's scheduler discipline. Use for any task touching app/jobs/workflow_scheduler_job.rb, app/services/scheduling/**, config/sidekiq.yml, config/schedule.yml, or the scheduler concurrency specs (spec/jobs/workflow_scheduler_job_spec.rb, spec/services/scheduling/**).
---

# ai-worker-scheduling

The delayed-UAT browser-test phase is specialised in `ai-worker-browser-tests`.

Scope:

- `app/jobs/workflow_scheduler_job.rb` enqueues on `stage_execution` and forwards each tick to `Scheduling::Tick` via `perform(run_workflow_id = nil, tick: nil)` (default tick built with `max_capacity: max_concurrent_agents`; specs pass `tick:`).
- `app/services/scheduling/active_workflow_runner.rb` polls running workflows and starts eligible active workflows; `stage_executor(executor_class:)` supplies its injectable current-stage executor (with `DEFAULT_EXECUTOR` retained as the compatibility alias).
- `app/services/scheduling/capacity.rb` tracks global slots and busy clones.
- `app/services/scheduling/guarded_executor.rb` logs and isolates individual executor failures.
- `app/services/scheduling/planner.rb` makes pure eligibility and `clone_key` decisions.
- `app/services/scheduling/post_merge_phase.rb` confirms tracked merges and starts one merged workflow when idle.
- `app/services/scheduling/tick.rb` runs ActiveWorkflowRunner, PostMergePhase, then UatPhase for one scheduler tick; accepts `active_runner_class:`, `post_merge_phase_class:`, `uat_phase_class:` factories (and optional instance overrides).
- `app/services/scheduling/uat_phase.rb` schedules due or retried UAT tests within free slots; its `clock:` seam passes a fixed `now:` to the due-UAT query in specs.
- `app/services/scheduling/workflow_queries.rb` provides the AR selections, ordering, due-UAT relation (with a `now:` seam), and free-slot count.
- `config/sidekiq.yml` serializes scheduler ticks.
- `config/schedule.yml` defines the cron cadence; `spec/config/sidekiq_schedule_spec.rb` asserts every entry parses with Fugit and has exactly five time fields (plus an optional time-zone token).
- `spec/services/scheduling/tick_spec.rb` covers phase order, named-workflow forwarding, and max_capacity defaults via injected `*_class:` factories.

What a started stage does is `StageExecutor` (`ai-worker-stage-pipeline`; stage-type wiring: `ai-worker-stage-types`). The code wins over `docs/RUNBOOK.md`.

## Tick

`WorkflowSchedulerJob#perform(run_workflow_id = nil, tick: nil)` is cron-driven on the `stage_execution` queue (`schedule.yml`: every 2 minutes, in two entries for working hours 05–13 and off-hours, Asia/Ho_Chi_Minh). Cron and `perform_later` pass no keywords; the default builds `Scheduling::Tick` with `max_capacity: max_concurrent_agents`. It walks every in-flight workflow in `position` order and never blocks on an agent. Three phases, in order:

1. **Active workflows** — `Scheduling::ActiveWorkflowRunner` handles `implementing`/`reviewing`/`local_testing`, plus `merged`/`uat_testing` ones that are `processing`. Running ones are executed (polled) first so finished runs free their slot and clone; then eligible waiting ones are started while `Scheduling::Capacity#can_start?` holds, calling `started!` only if the workflow is `processing` after `execute`.
2. **Post-merge** — `Scheduling::PostMergePhase` is skipped while any workflow is `implementing`/`local_testing` or any is `processing`. Otherwise `confirm_merges` runs `Stages::MergeCheck` for `done` development workflows with a PR URL that `tracks_jira_after_merge?`, then one non-processing `merged` workflow (lowest position) is executed.
3. **UAT** — `Scheduling::UatPhase` uses free slots = `max_concurrent_agents` (i.e. `Scheduling::Capacity.default_max`) minus all `processing` workflows (no idle wait, no clone check). Due = `uat_waiting` with `uat_test_at` passed (moved to `uat_testing` first) or `uat_testing` and not processing (a failed attempt retried); ordered by `uat_test_at`, limited to the free slots.

`execute` rescues `StandardError` per workflow and logs `[scheduler]`, so one failure never stops the tick.

## Eligibility (`Scheduling::Planner.eligible_waiting`)

- Heads = the first (by position) *development* workflow in `active_workflows` per clone; a head waiting on review keeps its slot, so later development workflows on that clone don't start. `active_workflows` must be in `position` order.
- PR-review workflows are always eligible (they neither hold nor wait on the head); only a running agent on the same clone blocks them, via `Capacity`.
- Runbooks are eligible only if `auto_run?` or `id == run_workflow_id` (the "Run stage" button); they never become heads.

## Capacity and clone key

- `Scheduling::Capacity.new(busy_clones:, max:)`: can start iff `active_count < max` and the workflow's `clone_key` isn't busy. `busy_clones` is built from all `processing` workflows (all statuses, so a running `merged`/UAT run counts) and the initial list is copied, not mutated. `max` defaults to `Scheduling::Capacity.default_max(env: ENV)`, which owns the `MAX_CONCURRENT_AGENTS` read (default 3); `WorkflowSchedulerJob.max_concurrent_agents` is a one-line forwarder to it. Specs pass `env:` a hash.
- `Scheduling::Planner.clone_key(project)` = `realpath` of the expanded `local_directory` if it exists, else the expanded path. Always go through it; never compare raw `local_directory` strings.

## Concurrency-1 contract

Capacity and head-of-line checks aren't atomic, so ticks must serialize: `config/sidekiq.yml` keeps `:concurrency: 1` (production runs a dedicated `-c 1 -q stage_execution` process, see `docs/RUNBOOK.md`). Parallelism comes from detached agent processes. Don't relax one rule (per-clone, global max, development one-at-a-time) without revisiting the others, and don't move the scheduler off the `stage_execution` queue.

## Specs

| Rule | Spec |
|---|---|
| Poll running before starting waiting | `spec/services/scheduling/active_workflow_runner_spec.rb` "polls processing workflows before starting waiting ones" |
| One start per shared clone | `spec/services/scheduling/active_workflow_runner_spec.rb` "starts only one waiting workflow per shared clone" |
| Global max | `spec/services/scheduling/active_workflow_runner_spec.rb` "stops starting workflows once the slot is taken" |
| Per-workflow failure isolation | `spec/services/scheduling/guarded_executor_spec.rb` "logs and swallows StandardError" |
| Post-merge idle gate, confirm + start one | `spec/services/scheduling/post_merge_phase_spec.rb` "is skipped while work is in progress", "only checks jira-tracked done workflows that have a pr_check stage", and "executes only the first merged workflow" |
| UAT due/retry and slot limit | `spec/services/scheduling/uat_phase_spec.rb` "moves due uat_waiting workflows to uat_testing and executes them", "retries idle uat_testing workflows", and "executes only the earliest due workflow" |
| Named non-auto-run runbook | `spec/services/scheduling/active_workflow_runner_spec.rb` "starts a named non-auto-run runbook only when named" |
| Head-of-line, PR-review exemption, runbook rules | `spec/services/scheduling/planner_spec.rb` `.eligible_waiting` |
| Clone-key normalisation | `spec/services/scheduling/planner_spec.rb` `.clone_key` |
| Slot/clone bookkeeping | `spec/services/scheduling/capacity_spec.rb` |

Run with `RAILS_ENV=test bundle exec rspec spec/jobs/workflow_scheduler_job_spec.rb spec/services/scheduling`. A new rule goes in the pure `Planner`/`Capacity` first (with a spec there) and gets a job-level spec only for phase wiring.
