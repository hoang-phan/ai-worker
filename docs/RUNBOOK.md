# Runbook

## Running Sidekiq

`config/sidekiq.yml` declares two queues: `default` and `stage_execution`.
In production, run `stage_execution` as its own process at concurrency 1,
separate from everything else:

```
bundle exec sidekiq -C config/sidekiq.yml -q default -c 5
bundle exec sidekiq -C config/sidekiq.yml -q stage_execution -c 1
```

Why: every `WorkflowSchedulerJob`/`StageExecutor` run blocks its thread on
a `claude -p` invocation that can take minutes (this app made a deliberate
"blocking call, no spawn+poll" tradeoff — see `docs/ARCHITECTURE.md`). If
that queue shared a thread pool with anything else, a slow implementation
run would starve unrelated jobs. Concurrency 1 also means at most one
workflow's stage executes at a time — matches "the first active workflow"
semantics; there's no need for the `Workflow#processing` guard to also
defend against Sidekiq itself pulling two jobs concurrently, though it
still defends against a run outlasting a single 30-minute cron tick.

## Reading `StageRun` history

Every stage execution attempt writes exactly one `StageRun`, visible on a
workflow's show page (`/projects/:id/workflows/:id`). `action` tells you
what happened:

- `ran_implementation` — implementation stage completed, PR opened.
- `approved_closed` — pr_check saw an approval; workflow is now `closed`.
- `requested_changes_fixed` — pr_check saw requested changes, ran a fix,
  re-requested review. Expect another one of these (or `approved_closed`)
  on a later tick.
- `no_action_pending` — pr_check ran but the PR has no decision yet
  (review not submitted). Normal, not an error.
- `failed` — something raised (`Git::CommandError`, `Github::CommandError`,
  `ClaudeCli::CommandError`, or a missing prompt template). Check the
  `error` column. The stage is left in `failed` status and
  `WorkflowSchedulerJob` will **not** retry it automatically.

## Unsticking a failed stage

From `bin/rails console`:

```ruby
stage = Stage.find(...)
stage.update!(status: :pending)   # re-queues it for the next 30-minute tick
```

Fix whatever caused the failure first (bad branch state in the project's
local clone, `gh`/`claude` auth expired, etc.) — re-queuing without fixing
the underlying cause just fails again next tick.

## Manually running a stage right now

Don't wait for the cron tick:

```ruby
workflow = Workflow.find(...)
StageExecutor.new(workflow, workflow.next_stage).call
```

## If a workflow needs to be abandoned

Set `status: :closed` directly (`workflow.update!(status: :closed)`) — the
scheduler only ever looks at `Workflow.active`, so this immediately stops
it being picked up, regardless of what state its stages are in.
