---
name: ai-worker-brainstorm
description: Applies ai-worker's Brainstorm subsystem discipline. Use for any task touching app/services/brainstorm/**, app/jobs/brainstorm_job.rb, app/controllers/project_brainstorms_controller.rb, spec/services/brainstorm/** or spec/jobs/brainstorm_job_spec.rb — Brainstorm::Planner, RunLifecycle, RunOutcome, LaunchContext, Prompt, ProposalImporter, BrainstormJob and the "Brainstorm now" button.
---

# ai-worker-brainstorm

Scope: the goal-driven, read-only agent that proposes new workflows for a personal project. It is built on `AiCli::DetachedRun` like the Jira/Slack/Bugsnag fetchers but has a different shape: `Planner` → `RunLifecycle` (one retry) → `RunOutcome`, not fetcher + sync wrapper. The shared `DetachedRun` contract, `AgentRuns::*` and the checklist for the fetch/sync services are in `ai-worker-detached-agent-runs`; the `AiCli` runner/poller in `ai-worker-agent-cli`; shared subprocess/error conventions in `ai-worker-orchestration`; spec rules in `ai-worker-testing`; the `Project` brainstorm columns in `ai-worker-domain`; the "Brainstorm" project-page UI in `ai-worker-ui`; prompt templates are unrelated (`Brainstorm::Prompt` is plain code, not a `PromptTemplate`) — not repeated here.

## Moving parts

- `app/services/brainstorm/planner.rb` (`Brainstorm::Planner`, also defines `Brainstorm::FetchError`) — the public surface: `running?`, `last_started_at` (delegated to the lifecycle), `blockers`, `queued_count`, `wait_reason`, `record_start!`, `start`, `poll`, `import`. Owns `ROOT = tmp/brainstorms`, `STALE_AFTER` (45 min), the read-only `ALLOWED_TOOLS`, and `Planner.model` / `Planner.effort`. `Result` is `ProposalImporter::Result`.
  - `ALLOWED_TOOLS` = `Read`, `Grep`, `Glob`, `Write` (for the result file only), `Bash(git log:*)`, `Bash(git ls-files:*)`, `Bash(git status:*)`, `Bash(git diff:*)`. Nothing that edits code, branches, commits, PRs or posts. Widening it, or the prompt's "read-only" wording, needs a reason.
  - `Planner.model` / `Planner.effort` read `BRAINSTORM_MODEL` / `BRAINSTORM_EFFORT` (blank counts as unset) and fall back to `DEFAULT_MODEL` / `DEFAULT_EFFORT` — a stronger model and higher effort than workflow runs. Tests that care about them set the env; never hard-code a model name elsewhere.
  - `blockers` = `Projects::RunBlockers.new(project).messages(:personal_kind, :brainstorm_goal, :local_directory)` (`app/models/projects/run_blockers.rb`).
  - **Queued-workflow gate**: `wait_reason` is nil only when `project.workflows.queued.count` is zero; otherwise `"N workflow(s) still pending; start or delete them first."`. Proposals wait for a human to Start them. `ProposalImporter` re-checks the queue at import time. Implementing workflows do *not* block it.
  - `record_start!` stamps `brainstorm_last_run_at` via `clock.current`; callers invoke it only after a successful `start`.
  - `start`/`poll` build one `LaunchContext` per attempt and pass `prepare: -> { write_history(context) }` plus `launch_inputs` (`cwd: project.local_directory`, prompt, `allowed_tools`, `model`, `effort`) to the lifecycle; `poll` filters rows with `Workflows::ProposalNormalizer.call` (owned by `ai-worker-domain`).
- `app/services/brainstorm/run_lifecycle.rb` (`Brainstorm::RunLifecycle.new(dir:, stale_after:, error_class: FetchError, run: nil, runner: AiCli::Runner)`) — owns the on-disk state and wraps one memoised `AiCli::DetachedRun` (`result_name: "result.json"`). `start(prepare: nil, **launch_inputs)` is false while running; otherwise it mkdirs the dir, removes the `retried` marker, truncates `agent.log`, runs `prepare`, launches. `poll` returns nil when there is no `pid`; if the process ended without `result.json` it clears the pid and `retry_missing_result`; otherwise delegates to `run.poll(&block)`. **One retry**: if `RunOutcome#retry?`, touch `retried`, re-run `prepare`, relaunch, return nil; else raise `error_class` with "agent wrote no result.json (<reason>); see <agent.log>".
- `app/services/brainstorm/run_outcome.rb` (`RunOutcome.new(log_path:, retried:)`) — read-only view of `agent.log` (stream-json): the last line starting `{"type":"result"`, `retry?` (true only for `terminal_reason == "aborted_streaming"` and not already retried), `failure_reason` (`subtype/terminal_reason`, or "no result event in the log"). Invalid JSON or a missing log gives no event. It never writes; the lifecycle owns the `retried` marker.
- `app/services/brainstorm/launch_context.rb` (`LaunchContext`) — plain value snapshot of the implementing workflows for one attempt: `from_workflows` (newest first, one `"- #{workflow.brief}"` line each), `lines`, `total`, `history_text`, `prompt_inputs`. The prompt and `history.md` derive from the same list so they cannot disagree.
- `app/services/brainstorm/prompt.rb` (`Prompt`, pure: plain values, no DB/filesystem) — the agent text. Shows the newest `HISTORY_LINES` (30) in-flight lines, points at `history.md` for the rest, states the read-only rule, the goal, the `max_workflows` cap, spells out the absolute `result_file`, the row shape, `[]` for nothing and a one-line reply.
- `app/services/brainstorm/proposal_importer.rb` (`ProposalImporter.new(project, in_flight:).call(proposals)`) — returns a `Result` (`created`, `skipped`, `summary` = "created N, skipped M"). Does nothing if a queued workflow exists; skips summaries matching an in-flight workflow's `brief` or an earlier proposal in the batch (normalised lowercase alphanumerics); stops at `project.brainstorm_max_workflows` *created* (skipped ones don't count); builds with `skills` = `project.default_skills` then the proposal's skills, deduped (defaults alone when none), status `implementing` if `brainstorm_auto_start?` else `pending`, `project.next_workflow_position`; a workflow that fails validation lands in `skipped` with its errors.
- `app/jobs/brainstorm_job.rb` (`BrainstormJob`, queue `default`) — for every `Project.personal.where(brainstorm_enabled: true)` runs `AgentRuns::SyncCycle` with the planner (poll → import → persist `brainstorm_last_result` / `"failed: ..."` → idle/`due: wait_reason.nil?`/blockers → start → `record_start!`), rescuing `Brainstorm::FetchError` and `AiCli::CommandError`. `config/schedule.yml` entry `brainstorm` is `*/30 * * * *` on `default` (the code comments say "hourly"; the cron wins). Never waits on the agent.
- `app/controllers/project_brainstorms_controller.rb` (`POST /projects/:id/brainstorm`, `config/routes.rb`) — "Brainstorm now": one `ManualStartFlash#start_manually` call (`AgentRuns::ManualStart` with the planner's `blockers`, `wait_reason`, `start`, `record_start!`); `@project` comes from `ProjectMemberScoped`. It only starts; `BrainstormJob` imports the result. Views: `app/views/projects/_brainstorm.html.erb`, `app/views/projects/form/_brainstorm.html.erb`.

## State layout

Per project under `tmp/brainstorms/<project id>/` (`ROOT` joined with the id):

- `pid`, `started_at` — written by `DetachedRun`.
- `agent.log` — the agent's stream-json output; `RunOutcome` reads its final `result` event.
- `result.json` — a JSON array and nothing else (`[]` = nothing worthwhile); each element `{"summary", "task", "skills"?}`. Missing file / bad JSON / non-array / stale run raises `FetchError`.
- `history.md` — `LaunchContext#history_text`, one `- brief` line per implementing workflow, newest first; rewritten on every start and on the retry.
- `retried` — marker that the one retry has been used; removed by the next `start`.

## Conventions

- Follow `RunLifecycle`/`DetachedRun`, never local pid-file handling. Keep `Prompt`, `LaunchContext` and `RunOutcome` free of the DB and (except `RunOutcome`'s log read and the lifecycle's own files) the filesystem.
- Injection seams — use them in specs instead of `stub_const` or `allow(X).to receive(:new)`: `Planner.new(project, clock: Time, root: ROOT, lifecycle: nil)`; `RunLifecycle.new(dir:, stale_after:, error_class:, run: nil, runner: AiCli::Runner)`; `ProposalImporter.new(project, in_flight:)`; `RunOutcome.new(log_path:, retried:)`.
- User free text (the goal) goes into the prompt as data; never interpolate it into a shell string and never put secrets in it.
- Imported workflows are `pending` unless the project opts into `brainstorm_auto_start?`; never bypass the queued gate or the max cap.
- New proposal fields: extend `Workflows::ProposalNormalizer`, `Prompt`'s example row and `ProposalImporter#build` together.

## Spec recipe

- `spec/services/brainstorm/planner_spec.rb`: tmp `root:` via `make_tmpdir`, an `instance_double(Brainstorm::RunLifecycle, running?:, last_started_at:, start:, poll:, result_path:)` as `lifecycle:`, and a `double("clock", current: at)` for `record_start!`.
- `spec/services/brainstorm/run_lifecycle_spec.rb`: tmp dir, `runner: instance_double(AiCli::Runner.singleton_class)` (or a fake `run:`), hand-written `pid`, `agent.log` and `result.json`; cover the single retry on `aborted_streaming`, no second retry, and the `FetchError` message.
- `run_outcome_spec.rb` writes `agent.log` lines; `prompt_spec.rb` feeds plain values/rows; `proposal_importer_spec.rb` covers queue gate, cap, dedupe, auto-start status and validation failures.
- `spec/jobs/brainstorm_job_spec.rb`: stub `AgentRuns::SyncCycle.call`; assert it selects only enabled personal projects and calls it once per project with `Brainstorm::CycleSource`, the exact prefix, and `[ Brainstorm::FetchError, AiCli::CommandError ]`. Retain at most one thin real-cycle example for expected-error persistence and continuation; keep queue/blocker/start ordering, summaries, and `brainstorm_last_run_at` in the cycle-source/planner/`AgentRuns` specs. `spec/requests/project_brainstorms_spec.rb` covers the button.
- Run with `RAILS_ENV=test bundle exec rspec spec/services/brainstorm spec/jobs/brainstorm_job_spec.rb spec/requests/project_brainstorms_spec.rb`.

## Safety

- Never start a real brainstorm (`planner.start`, the button, `BrainstormJob.perform_now`) against a real project to try it — use a fake `lifecycle:`/`runner:` and a tmp `root:`. No scratch scripts or `rails runner` against the development DB; every command sets `RAILS_ENV=test`.
- Don't delete or hand-edit real `tmp/brainstorms/<id>` dirs; a stale pid is cleared by `poll`. Specs create projects with unique names and remove only their own tmp dirs.
- The run is read-only by design: keep `ALLOWED_TOOLS` and the prompt's no-change rule in step, and no secrets in prompts, `history.md` or `result.json`.
