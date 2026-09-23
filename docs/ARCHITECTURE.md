# Architecture

## Data model

```
Project 1---* Workflow 1---* Stage 1---* StageRun

PromptTemplate  (referenced by Stage#prompt_template_id, or by stage_type default)
```

- **Project** — `name`, `local_directory` (an existing local clone, on `main`), `repo_full_name` (`org/repo`, used for `gh -R`).
- **Workflow** — one Jira ticket's automation run: `jira_ticket`, `branch_name`, `github_reviewer`, `skills` (comma-separated, rendered into `{SKILLS}`), `github_pr_url` (set once the implementation stage runs), `status` (`active`/`closed`), `position` (manual FIFO ordering), `processing` (overlap guard). Creating a Workflow auto-creates its two `Stage`s: `implementation` (position 1) and `pr_check` (position 2).
- **Stage** — `stage_type` (`implementation`/`pr_check`), `status` (`pending`/`in_progress`/`completed`/`failed`), `position`, optional `prompt_template_id` (falls back to the active default template for its `stage_type` — `Stage#effective_template`).
- **StageRun** — one audit-log row per execution attempt. Since `pr_check` can run every 30 minutes for a long time, this is where its history lives, not on the `Stage` row itself. `action` is one of `StageRun::ACTIONS`.
- **PromptTemplate** — `name`, `stage_type`, `body` (contains `{JIRA}`/`{PR}`/`{REVIEWER}`/`{SKILLS}`), `active` (exactly one active template per `stage_type`; saving a new active one deactivates the previous).

## Scheduling

`config/schedule.yml` registers `WorkflowSchedulerJob` with sidekiq-cron, firing every 30 minutes.

`WorkflowSchedulerJob#perform`:
1. `workflow = Workflow.active.order(:position).first` — the first active workflow, FIFO by `position`.
2. Skip this tick if `workflow.processing?` — a prior run (e.g. a slow implementation) is still going.
3. `stage = workflow.next_stage` — the first `pending` stage in `position` order. Skip if none.
4. Set `processing = true`, run `StageExecutor.new(workflow, stage).call`, clear `processing` in an `ensure`.

## Stage execution

`StageExecutor` (`app/services/stage_executor.rb`):

**`implementation`**
1. `Git::BranchService.create_branch!(project, workflow.branch_name)` — fetches `origin/main` and creates (or resumes) the branch, in `project.local_directory`.
2. Render the stage's effective template (`Prompts::Renderer`) — `{PR}` is blank at this point.
3. `ClaudeCli::Runner.run(project.local_directory, prompt)` — blocking `claude -p` run. The prompt itself instructs Claude to implement the ticket **and** open the PR (`gh pr create`).
4. `Github::Client#pr_url_for_branch` reads back the PR URL via `gh pr view --json url`, stored on the workflow.
5. Stage → `completed`; `StageRun(action: "ran_implementation")`.

**`pr_check`**
1. `Github::Client#review_decision` reads `gh pr view --json reviewDecision`.
2. `APPROVED` → workflow → `closed`, stage → `completed`, `StageRun(action: "approved_closed")`. No further stages run.
3. `CHANGES_REQUESTED` → re-checkout the branch, render the `pr_check` template (tells Claude to fetch review comments via `gh pr view --json reviews,comments`, fix them, commit, push), run `claude -p`, then `Github::Client#request_review!` (there's no plain `gh pr` subcommand for this, so it's a `gh api .../requested_reviewers` call). `StageRun(action: "requested_changes_fixed")`. Stage stays `pending` — runs again next tick.
4. Anything else (no review yet) → `StageRun(action: "no_action_pending")`. Stage stays `pending`.

Any `Git::CommandError` / `Github::CommandError` / `ClaudeCli::CommandError` / `ArgumentError` raised anywhere in the above is caught by `StageExecutor#call` itself: the stage is marked `failed` and a `StageRun(action: "failed", error: ...)` is written, instead of crashing the Sidekiq job.

## Why Sidekiq instead of Solid Queue

Rails 8 ships with Solid Queue/Cache/Cable by default and this app was
generated with them, but the recurring-schedule requirement was specified
as "Sidekiq worker" explicitly, so Sidekiq + `sidekiq-cron` + Redis were
added and `config.active_job.queue_adapter` was switched to `:sidekiq`
(Solid Cache/Cable are untouched — only the job backend changed).

## Why a blocking call, not spawn+poll

`ClaudeCli::Runner` runs `claude -p` synchronously via `Open3.capture3` and
blocks the calling Sidekiq thread until it exits — simpler than tracking a
detached process handle across job runs. The tradeoff (a slow
implementation ties up a worker thread) is mitigated operationally: run
`stage_execution` on its own low-concurrency Sidekiq process rather than
sharing threads with anything else (see `docs/RUNBOOK.md`).
