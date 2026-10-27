---
name: ai-worker-review
description: Checklist for reviewing ai-worker changes before opening a pull request.
---

# ai-worker review checklist

## Subprocess safety
(For git/gh specifics — `Git::Shell`, `Github::Runner`, CommandError conventions — see the `ai-worker-git` skill.)
- No `Open3`/`system`/backtick call builds a `cd X && ...` compound shell string. Every call passes `chdir:` (Ruby) or uses `git -C <dir>` / `gh -R org/repo` (CLI flag) instead.
- Every subprocess call checks the exit status and raises a scoped `CommandError` on failure rather than silently swallowing a non-zero exit.

## Stage/workflow invariants
- `StageExecutor` never lets a `Git::CommandError`, `Github::CommandError`, `AiCli::CommandError`, or `ArgumentError` escape uncaught — it must land in the `rescue` that calls `Stages::FailureHandler`, which marks the stage `failed` and writes a `StageRun`.
- Stages have no status column; progress is the workflow's `status`. A `pr_check` outcome only moves the workflow on for `APPROVED` (→ `done`, unless checks fail or a local test failed, which count as changes requested) or a merged PR (→ `merged`). Every other outcome (`CHANGES_REQUESTED`, no decision yet) must leave the workflow in `reviewing` so `WorkflowSchedulerJob` picks it up again next tick.
- Every path that finishes or fails an agent run clears the run-tracking columns (`processing`, pid, log path, start time, log offset, provider) through `Workflow#finish_ai_run!` (which merges `Workflow::AI_RUN_RESET`) — the `Stages::*Finish` classes do this on success and `Stages::FailureHandler` on failure, not `StageExecutor` itself. Otherwise the workflow stays "running" and is polled forever. The scheduler itself only rescues per workflow so one failure never stops the tick.
- Every path that starts a run, finishes one, or reaches a decision (including "no decision yet") writes at least one `StageRun` via `Stage#log_run!` with an `action` from `StageRun::ACTIONS` — these live in `Stages::StartHandler`, `Stages::CompletionHandler` and the `Stages::*Finish` / `*Start` services. No silent paths, and no action string missing from that list.

## Data/model
- New enum values are additive (new members added, existing numeric values never renumbered) — `Stage#stage_type`, `PromptTemplate#stage_type` (reuses the single `Stage::STAGE_TYPES` mapping), `Workflow#status`/`#kind` and `Project#kind` are persisted as integers via Rails `enum`, so reordering breaks existing rows.
- New required-for-control-flow columns (status/kind/position/`processing`/enable flags) have `null: false, default:` in their migration.

## UI
- Forms never expose `github_pr_url` as an editable field — it's system-set.
- Enum-backed selects use `Model.enum_name.keys`, not a hardcoded string list.

## Structure
(Rules live in `ai-worker-refactoring` and `ai-worker-testing`; check the diff follows them.)
- One class per file, with the file path matching the constant.
- Every new class has its own spec.
- The owning skill's file map is updated in the same commit.
- Specs run with `RAILS_ENV=test`, use `let_tmpdir` and `RecordHelper`, and never do destructive cleanup (`destroy_all`, `delete_all`, ...).

## Docs
- If a placeholder (see `ai-worker-prompts`) or a `StageRun::ACTIONS` value changed, `docs/PROMPT_TEMPLATES.md` is updated to match.
