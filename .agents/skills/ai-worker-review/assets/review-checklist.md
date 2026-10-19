# ai-worker review checklist

## Subprocess safety
- No `Open3`/`system`/backtick call builds a `cd X && ...` compound shell string. Every call passes `chdir:` (Ruby) or uses `git -C <dir>` / `gh -R org/repo` (CLI flag) instead.
- Every subprocess call checks the exit status and raises a scoped `CommandError` on failure rather than silently swallowing a non-zero exit.

## Stage/workflow invariants
- `StageExecutor` never lets a `Git::CommandError`, `Github::CommandError`, `AiCli::CommandError`, or `ArgumentError` escape uncaught — it must land in the `rescue` that marks the stage `failed` and writes a `StageRun`.
- A `pr_check` stage is only ever marked `completed` on the `APPROVED` path (which also closes the workflow). Every other `pr_check` outcome (`CHANGES_REQUESTED`, no decision yet) must leave the stage `pending` so `WorkflowSchedulerJob` picks it up again next tick.
- `WorkflowSchedulerJob` must always clear `workflow.processing` in an `ensure`, even on failure — otherwise a workflow gets stuck skipped forever.
- Every `StageExecutor` code path that actually attempts work (implementation run, PR-check decision) writes exactly one `StageRun` with an `action` from `StageRun::ACTIONS` — no silent no-op paths outside the documented "no decision yet" case.

## Data/model
- New enum values are additive (new members added, existing numeric values never renumbered) — `Stage#status`/`#stage_type` and `Workflow#status` are persisted as integers via Rails `enum`, so reordering breaks existing rows.
- New required-for-control-flow columns (status/position/active-style) have `null: false, default:` in their migration.

## UI
- Forms never expose `github_pr_url` as an editable field — it's system-set.
- Enum-backed selects use `Model.enum_name.keys`, not a hardcoded string list.

## Docs
- If a placeholder (`{JIRA}`, `{PR}`, `{REVIEWER}`, `{SKILLS}`) or a `StageRun::ACTIONS` value changed, `docs/PROMPT_TEMPLATES.md` is updated to match.
