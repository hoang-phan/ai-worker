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

The server-wide `AGENT` env var (`claude` or `cursor`, default `claude`) selects
which CLI `AiCli::Runner` spawns for every workflow, e.g. `AGENT=cursor bin/dev`
(set it for both the web and Sidekiq processes; foreman passes it to both). The commands live in `AiCli::Runner::AGENTS`:

| agent  | command                                      |
|--------|----------------------------------------------|
| claude | `claude -p "<prompt>" --dangerously-skip-permissions` |
| cursor | `agent -p "<prompt>" --force`                |

Adding another CLI (e.g. OpenAI Codex, likely `codex exec ...`) means one
entry in `AGENTS`. `AI_VERBOSE`
stream-json output only applies to `claude`.
