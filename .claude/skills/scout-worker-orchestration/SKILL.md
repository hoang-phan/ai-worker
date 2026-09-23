---
name: scout-worker-orchestration
description: Applies scout-worker's job/service discipline. Use for any task touching app/jobs/**, app/services/**, config/sidekiq.yml, or config/schedule.yml — the scheduler job, StageExecutor, or the Git/Github/ClaudeCli/Prompts service objects.
---

# scout-worker-orchestration

Scope: `app/jobs/**`, `app/services/**`, `config/sidekiq.yml`, `config/schedule.yml`, `config/initializers/sidekiq.rb`. Read `app/models/workflow.rb` and `app/models/stage.rb` only for the public methods this layer calls (`next_stage`, `effective_template`, `skill_list`) — don't otherwise touch the model layer (that's `scout-worker-domain`'s scope) or the UI (`scout-worker-ui`'s scope).

## File map (the whole scope)

- `app/jobs/workflow_scheduler_job.rb` — the cron entry point (`config/schedule.yml` fires it every 30 min via sidekiq-cron). Picks `Workflow.active.order(:position).first`, skips if it's already `processing?` (overlap guard for a run that outlasts 30 minutes), finds `next_stage`, delegates to `StageExecutor`, always clears `processing` in an `ensure`.
- `app/services/stage_executor.rb` — the two stage behaviors:
  - `implementation`: create the branch, render the prompt, run `claude -p`, read back the PR URL via `gh`, mark the stage `completed`.
  - `pr_check`: read the PR's review decision via `gh`; `APPROVED` closes the workflow; `CHANGES_REQUESTED` re-runs `claude -p` against the review-fix template and re-requests review (stage stays `pending`, runs again next tick); anything else is a no-op (also stays `pending`).
  - Any `Git::CommandError` / `Github::CommandError` / `ClaudeCli::CommandError` / `ArgumentError` is caught here, marks the stage `failed`, and logs a `StageRun` — never let one of these bubble up and crash the Sidekiq job.
- `app/services/git/branch_service.rb` — creates/resumes a workflow's branch from `main` in the project's local clone.
- `app/services/github/client.rb` — read-only `gh pr view` calls plus the one write op with no plain `gh pr` subcommand: re-requesting review via `gh api .../requested_reviewers`. PR *creation* is never done here — it happens inside the `claude -p` run itself, per the implementation prompt template.
- `app/services/claude_cli/runner.rb` — the single place that shells out to `claude -p`. Blocking by design (see `docs/RUNBOOK.md` for why, and why that's mitigated with a dedicated Sidekiq queue rather than spawn+poll).
- `app/services/prompts/renderer.rb` — the only place `{JIRA}`/`{PR}`/`{REVIEWER}`/`{SKILLS}` get substituted.

## Conventions

- **Never build a shell command as a `cd X && ...` string.** Every subprocess call in this scope uses `Open3.capture3(*command, chdir: dir)` instead — that's how `Git::BranchService`, `Github::Client`, and `ClaudeCli::Runner` are all written. A compound `cd &&` string is fragile under Sidekiq (no interactive shell, no guaranteed shell quoting) and is the exact anti-pattern this app's own skills should not reproduce for target projects either.
- Each service raises its own `CommandError` subclass (`Git::CommandError`, `Github::CommandError`, `ClaudeCli::CommandError`) on a non-zero exit status rather than returning a boolean — `StageExecutor` is the single place that catches these and turns them into a `failed` stage + `StageRun` row. Don't rescue errors inside the service objects themselves.
- `WorkflowSchedulerJob` only ever acts on **one** workflow per tick (the first active one, in `position` order) and **one** stage within it (`next_stage`) — do not change it to batch-process multiple workflows without also revisiting the `processing` overlap guard.
- To test a change without actually invoking real `claude`/`gh`, do what was done originally: build a scratch local git repo (`git init`, one commit, `git remote add origin <same path>`), put a fake executable named `claude` earlier on `PATH`, and run the service/job via `bin/rails runner` — this exercises the real `Open3`/`chdir` plumbing without hitting the network or an LLM.
