---
name: ai-worker-orchestration
description: Applies ai-worker's job/service discipline. Use for any task touching app/jobs/**, app/services/**, config/sidekiq.yml, or config/schedule.yml — the scheduler and sync jobs, StageExecutor, and the Git/Github/AiCli/Ci/Prompts/Jira/Slack/Bugsnag/Brainstorm service objects.
---

# ai-worker-orchestration

Scope: `app/jobs/**`, `app/services/**`, `config/sidekiq.yml`, `config/schedule.yml`, `config/initializers/sidekiq.rb` (scheduler specifics: `ai-worker-scheduling`). Read `app/models/workflow.rb`, `stage.rb` and `project.rb` only for the public methods and enums this layer calls (`current_stage`, `effective_template`, `skill_list`, `advance!`, status/kind enums, project settings) — don't otherwise touch the model layer (`ai-worker-domain`) or the UI (`ai-worker-ui`). The overall design is in `docs/ARCHITECTURE.md` and `docs/RUNBOOK.md`; where they and the code disagree, the code wins.

## File map (the whole scope)

**Scheduling**
- `config/schedule.yml`, `config/sidekiq.yml`, `app/jobs/workflow_scheduler_job.rb`, `app/services/scheduling/**` — the scheduler tick, its eligibility/capacity rules and the concurrency-1 contract: see the `ai-worker-scheduling` skill. The Jira, Slack-review and Bugsnag sync jobs and the hourly brainstorm job (also in `schedule.yml`) run on `default`.
- `app/services/stage_executor.rb` — runs one workflow's current stage and never waits on the agent: `call` polls a running agent when `workflow.processing?`, else builds a `Stages::AiRunLauncher` and hands it to `Stages::StartHandler` (per-stage start paths) and the PR/conflict paths, `poll_ai_run` builds `tooling.poller_class` (from `Stages::RunTooling`: `AiCli::RunPoller` for agent runs, `Ci::CheckPoller` for `ci_check`) with the workflow's pid/log/offset state and persists the poller's `log_offset`, and `call` rescues every `Git::CommandError` / `Github::CommandError` / `AiCli::CommandError` / `ArgumentError` into `fail_stage`, which logs a `failed` `StageRun` — never let one bubble up and crash the Sidekiq job. Everything after the run lives in `app/services/stages/` (below). Per-stage start/finish touch points: see `ai-worker-stage-types`.
- `app/services/stages/ai_run_launcher.rb` — the single detached-agent launch path: calls `AiCli::Runner.start`, records processing/pid/log/start/offset state on the workflow and logs the StageRun action. `app/services/stages/start_handler.rb` — start path per stage type (branch/checkout setup and PR-check decision) and calls its injected launcher; the non-trivial start paths are their own services (`stages/browser_test_start.rb` for uat/local tests, `stages/pr_review_start.rb` for pr_review), same keyword-injected shape. `app/services/stages/completion_handler.rb` — only dispatches a finished run on stage type to its `Stages::*Finish` service (see the next entry). `stages/failure_handler.rb` — failed-stage logging, the `MAX_CONSECUTIVE_FAILURES` cap that parks a workflow as `errored`. `stages/pr_check_decision.rb` (pure PR-check decision), `stages/local_test_policy.rb` (pure local-test retry/outcome rules), `stages/review_handoff.rb` (best-effort reviewer Slack ping and auto-merge), `stages/workflow_run_gate.rb` (runbook `wait_for_workflow` gate), `stages/conflict_resolution_finish.rb` (conflict-resolution success path: merge must be committed, then starts the review-fix run; git and launcher injected), `stages/merge_check.rb` (scheduler's idle-tick `done` → `merged` PR check; github injected, never raises).
- `app/services/stages/*_finish.rb` — one success-path service per stage type (`implementation`, `pr_check`, `task`, `pr_review`, `jira_lifecycle`, `local_test`, `ci_check`, `simple_implementation`, `ci_verify`, `pr_opened`, `runbook_step`, plus `conflict_resolution_finish`): each decides the next workflow status, calls `workflow.finish_ai_run!` (status maps live in `Workflows::StageResolver`), logs the `StageRun` and runs best-effort follow-ups. Which one a new stage type needs: `ai-worker-stage-types`.
- `app/services/ci/**`, `app/services/ai_cli/**` (`RunPoller`, `RunLogs`, `LogTail`, `RunVerdict`, ...) and `app/services/stages/run_tooling.rb` — launching and polling the detached agent / CI command: see the `ai-worker-agent-cli` skill. `StageExecutor` takes `Stages::RunTooling.for(stage)` as `tooling:` (with `github:` / `git:`, all defaulted, so specs inject doubles); flow overview: `ai-worker-stage-types`.

**Agent CLI** — `app/services/ai_cli/**` (`Runner`, `Command`, `Output`, `BrowserTestRun`, `CursorMcpFile`, `DetachedRun`, the `CommandError` classes): see the `ai-worker-agent-cli` skill.

**Prompts**
- `app/services/prompts/**` — prompt building and `{TOKEN}` substitution (`StagePrompt`, `Renderer`, `Defaults`): see the `ai-worker-prompts` skill.

**Git / GitHub** — see the `ai-worker-git-github` skill (Git::Shell, Git::BranchService, Github::Client → Reader/Writer/PrLocator/Runner).

**Detached-agent sync services** (Jira/Slack/Bugsnag fetchers, sync wrappers, `AgentRuns::*`, Brainstorm, the Slack review ping) — the file map, shape and checklist live in the `ai-worker-detached-agent-runs` skill. `app/services/slack/web_client.rb` is a minimal bot-token `chat.postMessage` client with no caller in `app/` (only its spec), so don't route new Slack work through it.

**Jira worklogs** (REST with `JIRA_EMAIL` / `JIRA_ACCESS_TOKEN`: `Jira::WorklogClient`, `TimeLogger`, `TimeLogBatch`, `HoursSync`, `JiraHoursSyncJob`, `TimeLog`) — the file map, data flow and conventions live in the `ai-worker-jira-worklogs` skill.
- `app/jobs/application_job.rb` — Rails default base class.

## Conventions

- **Never build a shell command as a `cd X && ...` string.** Subprocesses use `Open3.capture3(*command, chdir: dir)` (Git/Github services) or `Process.spawn(..., chdir:)` with an argument array (agent runs: `ai-worker-agent-cli`). Never interpolate untrusted text (ticket text, Slack text, PR titles) into a shell string — pass it as an argument or in the prompt/env.
- Each service raises its own `CommandError` subclass on a non-zero exit instead of returning a boolean. `StageExecutor` is the one place that turns these into a `failed` `StageRun`; the sync jobs rescue their own `FetchError` / `AiCli::CommandError`. Don't rescue inside the Git/Github/Runner objects.
- Agent runs are detached and polled across ticks; a job must never block on one (state and start/finish rules: `ai-worker-agent-cli`).
- Scheduler concurrency rules (per-clone, `MAX_CONCURRENT_AGENTS`, head-of-line, Sidekiq concurrency 1): see `ai-worker-scheduling`.
- Every code path in `StageExecutor` that attempts work or reaches an outcome logs a `StageRun` whose `action` is in `StageRun::ACTIONS`. Add the new action to that constant (domain skill) *before* logging it — an unlisted action fails the model validation and turns into a crash or a bogus failure. Log through `stage.log_run!(action, output: nil, error: nil)` (on `Stage`) — never `stage.stage_runs.create!` directly and never a private `log` helper per service.
- A failed stage stays in its current workflow status so the next tick retries it; after `MAX_CONSECUTIVE_FAILURES` the workflow becomes `errored`, which the scheduler ignores until a person resumes it.
- Agents get the least tool access and secrets only as env vars: see `ai-worker-agent-cli`.
- Test with RSpec, not scratch runners. Put specs under `spec/services/**` or `spec/jobs/**` (stub `Open3`, `AiCli::Runner` and `Github::Client`, or use temp directories and temp git repos) and run `RAILS_ENV=test bundle exec rspec`. Never run scratch scripts, `bin/rails runner` or console code against the development DB, and never start a real agent against a real project to "try it".
