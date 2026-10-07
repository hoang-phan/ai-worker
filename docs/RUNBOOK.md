# Runbook

## Running Sidekiq

`config/sidekiq.yml` declares two queues: `default` and `stage_execution`.
In production, run `stage_execution` as its own process at concurrency 1,
separate from everything else:

```
bundle exec sidekiq -C config/sidekiq.yml -q default -c 5
bundle exec sidekiq -C config/sidekiq.yml -q stage_execution -c 1
```

Why: `WorkflowSchedulerJob` fires every 10 minutes (`config/schedule.yml`)
and always returns quickly — `StageExecutor` starts the agent CLI (`claude -p` or `agent -p --force`) detached
(`Process.spawn`, output redirected to a log file under `log/ai_runs/`)
and never waits on it, so a run than can take many minutes never ties up
the job past Sidekiq's job timeout (this app used to run it blocking via
`Open3.popen3`, which is exactly what got killed by that timeout — see
`docs/ARCHITECTURE.md`). Concurrency 1 on `stage_execution` still matches
"the first active workflow, one stage at a time" semantics, and the
`Workflow#processing` guard (now `ai_pid`/`ai_log_path`/
`ai_started_at`/`ai_log_offset` alongside it) is what blocks the
*next* tick from starting a second run while the current one is still
going — every tick either starts new work or polls the existing run, and
`Process.wait2(pid, Process::WNOHANG)` never blocks either way.

## Reading `StageRun` history

Every stage execution attempt writes at least one `StageRun`, visible on a
workflow's show page (`/projects/:id/workflows/:id`). `action` tells you
what happened:

- `started` — a the agent CLI (`claude -p` or `agent -p --force`) run was kicked off in the background for this
  stage. Expect a follow-up `ran_implementation`/`requested_changes_fixed`
  (success) or `failed` on a later tick — polling ticks in between that
  find the run still going don't write a `StageRun` row, only a
  `Rails.logger` line per new line of the agent's output.
- `ran_implementation` — implementation stage's the agent CLI (`claude -p` or `agent -p --force`) run finished
  successfully, PR opened. `output` has the full agent log.
- `approved_closed` — pr_check saw an approval; workflow is now `done`.
- `requested_changes_fixed` — pr_check saw requested changes, ran a fix,
  re-requested review. Expect another one of these (or `approved_closed`)
  on a later tick. `output` has the full agent log.
- `no_action_pending` — pr_check ran but the PR has no decision yet
  (review not submitted). Normal, not an error.
- `failed` — something raised (`Git::CommandError`, `Github::CommandError`,
  `AiCli::CommandError` — including a the agent CLI (`claude -p` or `agent -p --force`) run that exited
  non-zero, ran longer than `StageExecutor::STALE_AFTER` (3 hours), or
  whose exit status could no longer be determined — or a missing prompt
  template). Check the `error` column. `workflow.processing?` is cleared
  either way, so the next tick will retry from scratch rather than being
  permanently stuck polling a dead run.

- `halted` — the stage failed `StageExecutor::MAX_CONSECUTIVE_FAILURES`
  (3) times in a row, so the scheduler stopped retrying it (logged once).
- `resumed` — manual marker that resets the failure count (see below).

## Unsticking a failed stage

After 3 consecutive failures the stage is `halted` and ticks no longer
start new runs. Once the cause is fixed, resume it with:

```ruby
stage = Workflow.find(...).current_stage
stage.stage_runs.create!(action: "resumed")
```

A `failed` `StageRun` already clears `workflow.processing?` (see above),
so the next tick will retry it on its own (up to the halt limit above). Fix whatever caused
the failure first (bad branch state in the project's local clone,
`gh`/agent CLI auth expired, etc.) — the workflow's `status` (and therefore
`current_stage`) doesn't change on failure, so it just fails again next
tick otherwise.

## Manually running a stage right now

Don't wait for the cron tick:

```ruby
workflow = Workflow.find(...)
StageExecutor.new(workflow, workflow.current_stage).call
```

If this starts a the agent CLI (`claude -p` or `agent -p --force`) run, this call returns immediately (it
doesn't wait for `claude` to finish) — call it again (or wait for the next
cron tick) to poll it.

## If a workflow needs to be abandoned

Set `status: :done` directly (`workflow.update!(status: :done)`) — the
scheduler only looks at `implementing`/`reviewing` workflows, so this
immediately stops it being picked up. If a the agent CLI (`claude -p` or `agent -p --force`) run is still going
in the background (`workflow.processing?`), kill it first
(`Process.kill("TERM", workflow.ai_pid)`) since abandoning the
workflow this way doesn't do that for you.
