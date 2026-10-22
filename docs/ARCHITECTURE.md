# Architecture

## Data model

```
Project 1---* Workflow 1---* Stage 1---* StageRun

PromptTemplate  (referenced by Stage#prompt_template_id, or by stage_type default)
```

- **Project** — `name`, `local_directory` (an existing local clone, on `main`), `repo_full_name` (`org/repo`, used for `gh -R`).
- **Workflow** — one Jira ticket's automation run: `jira_ticket`, `branch_name`, `github_reviewer`, `skills` (comma-separated, rendered into `{SKILLS}`), `github_pr_url` (set once the implementation stage runs), `status` (`pending`/`implementing`/`reviewing`/`done`/`errored`/`merged`/`jira_updated`), `position` (manual FIFO ordering), `processing` (overlap guard). Creating a Workflow auto-creates its two `Stage`s: `implementation` (position 1) and `pr_check` (position 2).
- **Stage** — `stage_type` (`implementation`/`pr_check`), `status` (`pending`/`in_progress`/`completed`/`failed`), `position`, optional `prompt_template_id` (falls back to the active default template for its `stage_type` — `Stage#effective_template`).
- **StageRun** — one audit-log row per execution attempt. Since `pr_check` can run every 30 minutes for a long time, this is where its history lives, not on the `Stage` row itself. `action` is one of `StageRun::ACTIONS`.
- **PromptTemplate** — `name`, `stage_type`, `body` (contains `{JIRA}`/`{PR}`/`{REVIEWER}`/`{SKILLS}`), `active` (exactly one active template per `stage_type`; saving a new active one deactivates the previous).

## Scheduling

`config/schedule.yml` registers `WorkflowSchedulerJob` with sidekiq-cron, firing every 10 minutes.

`WorkflowSchedulerJob#perform`:
1. `workflow = Workflow.where(status: [:implementing, :reviewing]).order(:position).first` — the first in-flight workflow, FIFO by `position`.
2. `stage = workflow.current_stage` — the stage matching the workflow's current status. Skip if none.
3. `StageExecutor.new(workflow, stage).call` — always returns quickly (see below), so the job never blocks.

The job itself never checks `workflow.processing?` to decide whether to skip — `StageExecutor` does that, and either starts new work or polls existing work accordingly. This is what makes "the next scheduled action is blocked until the current stage completes" hold: while `processing?` is true, every tick polls the same in-flight run instead of starting a second one.

## Stage execution

`StageExecutor` (`app/services/stage_executor.rb`) — every tick either **starts** a stage's the agent CLI (`claude -p` or `agent -p --force`) run in the background, or **polls** one already in flight, never both, and never waits on the process itself:

**Starting (`workflow.processing?` false)**

*`implementation`*
1. `Git::BranchService.create_branch!(project, workflow.branch_name)` — fetches `origin/main` and creates (or resumes) the branch, in `project.local_directory`.
2. Render the stage's effective template (`Prompts::Renderer`) — `{PR}` is blank at this point.
3. `AiCli::Runner.start(...)` — `Process.spawn`s the agent CLI (`claude -p` or `agent -p --force`), stdout/stderr redirected to a log file under `log/ai_runs/`, and returns its pid immediately. The prompt itself instructs Claude to implement the ticket **and** open the PR (`gh pr create`).
4. `workflow.update!(processing: true, ai_pid:, ai_log_path:, ai_started_at:, ai_log_offset: 0)`; `StageRun(action: "started")`.

*`pr_check`*
1. `Github::Client#review_decision` reads `gh pr view --json reviewDecision`.
2. `APPROVED` → workflow → `done`, `StageRun(action: "approved_closed")`. No further stages run.
3. `CHANGES_REQUESTED` → re-checkout the branch, render the `pr_check` template (tells Claude to fetch review comments via `gh pr view --json reviews,comments`, fix them, commit, push), start the agent CLI (`claude -p` or `agent -p --force`) the same non-blocking way as above (`StageRun(action: "started")`).
4. Anything else (no review yet) → `StageRun(action: "no_action_pending")`.

**Polling (`workflow.processing?` true)**
1. If the run has been going longer than `StageExecutor::STALE_AFTER` (3 hours), `Process.kill("TERM", ...)` it and treat it as failed.
2. `AiCli::Runner.tail_new_lines` reads any new bytes from the log file since `ai_log_offset` and logs each line via `Rails.logger` (tagged `workflow=<id> stage=<id>`), advancing the offset — this is what "keeps logging the claude response" across ticks rather than only at the end.
3. `AiCli::Runner.poll(pid)` — a non-blocking `Process.wait2(pid, Process::WNOHANG)`. `:running` → nothing more to do this tick.
4. On completion: read the full log file as `output`, then finish the same way the old blocking path did — `implementation` looks up the PR URL and moves the workflow to `reviewing`; `pr_check` calls `Github::Client#request_review!`. Either way, clear `processing`/`ai_pid`/`ai_log_path`/`ai_started_at`/`ai_log_offset` and write the final `StageRun` (`"ran_implementation"` / `"requested_changes_fixed"`, with the full log as `output`).
5. A non-zero exit status (or an exit status we could no longer determine, e.g. after a Sidekiq restart orphaned the child) raises `AiCli::CommandError`.

Any `Git::CommandError` / `Github::CommandError` / `AiCli::CommandError` / `ArgumentError` raised anywhere in the above is caught by `StageExecutor#call` itself: the run-tracking columns are cleared, the stage's `StageRun(action: "failed", error: ...)` is written, instead of crashing the Sidekiq job.

## Why Sidekiq instead of Solid Queue

Rails 8 ships with Solid Queue/Cache/Cable by default and this app was
generated with them, but the recurring-schedule requirement was specified
as "Sidekiq worker" explicitly, so Sidekiq + `sidekiq-cron` + Redis were
added and `config.active_job.queue_adapter` was switched to `:sidekiq`
(Solid Cache/Cable are untouched — only the job backend changed).

## Why spawn+poll, not a blocking call

`AiCli::Runner` used to run the agent CLI (`claude -p` or `agent -p --force`) synchronously via `Open3.popen3`
and block the calling Sidekiq thread until it exited. That's simpler, but
Sidekiq kills jobs that run past its configured job timeout (5 minutes
here), and an implementation run can easily take longer than that — a
killed job meant a lost run with no record of what Claude did.

`Runner.start` now `Process.spawn`s the agent CLI (`claude -p` or `agent -p --force`) detached, redirecting its
output to a log file, and returns the pid immediately; the workflow rows
`ai_pid`/`ai_log_path`/`ai_started_at`/`ai_log_offset`
(all on `workflows`) are what let a *later*, independent job tick find and
poll that same process — `Process.wait2(pid, Process::WNOHANG)` never
blocks. `workflow.processing?` is reused as the "don't start a second run
on top of this one" guard, and now stays true across as many ticks as the
run takes, instead of only for the duration of one job.

## Agents

The server-wide `AGENT` env var (`claude`, `cursor` or `codex`, default `claude`) selects
which CLI `AiCli::Runner` spawns for every workflow, e.g. `AGENT=cursor bin/dev`
(set it for both the web and Sidekiq processes; foreman passes it to both). The commands live in `AiCli::Runner::AGENTS`:

| agent  | command                                      |
|--------|----------------------------------------------|
| claude | `claude -p "<prompt>" --dangerously-skip-permissions` |
| cursor | `agent -p "<prompt>" --force`                |
| codex  | `codex exec --dangerously-bypass-approvals-and-sandbox "<prompt>"` |

Adding another CLI means one entry in `AGENTS`. Codex's stdout/stderr go to the
same per-run log file as the others and are tailed into the Rails log.
Env vars can live in a git-ignored `.env` (see `.env.example`), loaded by `dotenv-rails`. `AI_VERBOSE`
stream-json output only applies to `claude`.

## Brainstormed workflows

Personal projects can have a standing goal (`projects.brainstorm_goal`, e.g. "improve the app UI", "increase test coverage", "suggest more useful functionality") with `brainstorm_enabled` on. `BrainstormJob` (hourly, `default` queue) works like `BugsnagSyncJob`: `Brainstorm::Planner` starts one detached, read-only agent run in the project's clone that writes `tmp/brainstorms/<project id>/result.json` (`[{summary, task, skills?}]`), and a later tick imports it as workflows (`summary` = the short line, `task_description` = the full task, `skills` = the project's `default_skills` plus any of the repo's own skill names the agent picked for that task), skipping summaries that match an existing workflow, up to `brainstorm_max_workflows`. They are created `pending` (press Start), or `implementing` with `brainstorm_auto_start`.

- It only runs while the project has no `pending` development workflow (`Workflow::QUEUED_STATUSES`). Implementing workflows don't block it, but aren't in the code yet, so only they are listed to the agent to avoid duplicates (done ones are already in the code it reads); other statuses are Jira-project concerns and irrelevant here.
- To keep the agent's context small it is given one short line per implementing workflow (`Workflow#brief`: `summary`, else the label, max 100 chars), newest 30 inline, all of them in `history.md` next to the result for grepping. Imported proposals are also deduped against those.
- `BRAINSTORM_MODEL` (default `claude-opus-5-5`) and `BRAINSTORM_EFFORT` (default `high`) in `.env` become `--model` / `--effort` through `AiCli::Runner.start(model:, effort:)`; claude only. Tools are limited to read/search, `git log/ls-files/status/diff` and `Write`.
- "Brainstorm now" on the project page triggers a run, under the same no-pending rule.

## PR-review workflows (Slack)

### Post-merge Jira update

`done`, `merged` and `jira_updated` all free the project for its next workflow. On a tick with no work in progress (nothing `implementing`, no agent running; workflows merely waiting on review don't count), `WorkflowSchedulerJob` (1) moves `done` Jira workflows whose PR is now merged to `merged` (`StageRun: pr_merged_detected`; `pr_check` also goes straight to `merged` if it finds the PR already merged), then (2) starts one `merged` workflow's `jira_update` stage (created lazily): the agent moves the ticket to UAT (UI-testable; assigns `Project#jira_tester`, sets Developer to the original assignee) or Releaseable, and must end with `JIRA_RESULT: UAT|RELEASEABLE`. Success → `jira_updated`; failures retry like any stage. Falls back to `Prompts::Defaults.for("jira_update")`; `{TESTER}` placeholder. The migration marks pre-existing done Jira workflows `jira_updated` so old tickets aren't touched. If the ticket went to UAT and the project has UAT testing enabled (`uat_test_enabled`, `uat_url`, `uat_username`, encrypted `uat_password`, `uat_test_delay_minutes`), the workflow goes to `uat_waiting` instead; `WorkflowSchedulerJob#run_uat_phase` starts the `uat_test` stage (status `uat_testing`, then `uat_tested`) once `uat_test_at` has passed, whenever an agent slot is free (it doesn't wait for idle, and never blocks the project's next workflow). See `docs/RUNBOOK.md`.

A second `Workflow#kind`, `pr_review`, reviews *someone else's* PR. It has one stage (`pr_review`) and goes `implementing` → `done` (or `errored`); it never uses `reviewing`.

- `SlackReviewJob` (every minute, `default` queue) works like `JiraSyncJob`: for each Jira-kind project with `slack_review_enabled`, `Slack::MentionFetcher` starts a detached agent run (Slack MCP) at most every 30 minutes — headless, with `claude -p --allowedTools` limited to the Slack read/search tools and `Write` (`Slack::MentionFetcher::ALLOWED_TOOLS`) rather than `--dangerously-skip-permissions`; the Slack connector must be authenticated for the user the server runs as — which writes the project's Slack mentions + the repo's PR URLs they (or their thread) contain to `tmp/slack_reviews/<project id>/mentions.json`. A later tick imports it via `Slack::ReviewSync`: one workflow per (Slack message, PR), skipping PRs that are closed/merged, authored by the `gh` user, or already imported (the project's "last result" says why, e.g. `skipped 3 (3 merged)`). Review workflows are created `implementing`, and the job enqueues `WorkflowSchedulerJob` right after creating any, so they start without waiting for the next */5 cron tick. "Sync now" on the project page triggers a fetch immediately.
- `StageExecutor#start_pr_review` checks the PR is still open, checks out its head branch in the project's clone (`git fetch` + checkout + `pull --ff-only`; fork PRs via `gh pr checkout`), then runs the agent with the `pr_review` prompt (`{PR}`, `{SLACK}`; falls back to `Prompts::Defaults.for("pr_review")`), which reviews, submits the GitHub verdict and replies in the Slack thread. Success → `review_completed`.
- Scheduling: same per-clone guard as every workflow (one running agent per `local_directory`). Review workflows are not blocked by a development workflow that is merely waiting on its PR, and don't hold the project's "head" slot.

## Runbook workflows

Workflows of kind `runbook` (any project, one per deployment) use their own user-defined stages that pause for a **Next** click; see `docs/RUNBOOK_WORKFLOWS.md`.
