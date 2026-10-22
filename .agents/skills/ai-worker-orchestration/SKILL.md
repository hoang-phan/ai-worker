---
name: ai-worker-orchestration
description: Applies ai-worker's job/service discipline. Use for any task touching app/jobs/**, app/services/**, config/sidekiq.yml, or config/schedule.yml — the scheduler and sync jobs, and the Git/Github/AiCli/Ci/Prompts/Jira/Slack/Bugsnag/Brainstorm service objects.
---

# ai-worker-orchestration

Scope: `app/jobs/**`, `app/services/**`, `config/sidekiq.yml`, `config/schedule.yml`, `config/initializers/sidekiq.rb` (scheduler specifics: `ai-worker-scheduling`). Read `app/models/workflow.rb`, `stage.rb` and `project.rb` only for the public methods and enums this layer calls (`current_stage`, `effective_template`, `skill_list`, `advance!`, status/kind enums, project settings) — don't otherwise touch the model layer (`ai-worker-domain`) or the UI (`ai-worker-ui`). The overall design is in `docs/ARCHITECTURE.md` and `docs/RUNBOOK.md`; where they and the code disagree, the code wins.

## File map (the whole scope)

**Scheduling**
- `config/schedule.yml`, `config/sidekiq.yml`, `app/jobs/workflow_scheduler_job.rb`, `app/services/scheduling/**` — the scheduler tick, its eligibility/capacity rules and the concurrency-1 contract: see the `ai-worker-scheduling` skill. The Jira, Slack-review and Bugsnag sync jobs and the hourly brainstorm job (also in `schedule.yml`) run on `default`.
- `app/services/stage_executor.rb` and `app/services/stages/**` (except `run_tooling.rb`) — stage execution, start/finish handlers, and `StageRun` conventions: see `ai-worker-stage-pipeline`.
- `app/services/ci/**`, `app/services/ai_cli/**` (`RunPoller`, `RunLogs`, `LogTail`, `RunVerdict`, ...) and `app/services/stages/run_tooling.rb` — launching and polling the detached agent / CI command: see the `ai-worker-agent-cli` skill. `StageExecutor` takes `Stages::RunTooling.for(stage)` as `tooling:` (with `github:` / `git:`, all defaulted, so specs inject doubles); flow overview: `ai-worker-stage-types`.

**Agent CLI** — `app/services/ai_cli/**` (`Runner`, `Command`, `Output`, `BrowserTestRun`, `CursorMcpFile`, `DetachedRun`, the `CommandError` classes): see the `ai-worker-agent-cli` skill.

**Prompts**
- `app/services/prompts/**` — prompt building and `{TOKEN}` substitution (`StagePrompt`, `Renderer`, `Defaults`): see the `ai-worker-prompts` skill.

**Git / GitHub** — see the `ai-worker-git-github` skill (Git::Shell, Git::BranchService, Github::Client → Reader/Writer/PrLocator/Runner).

**Detached-agent sync services** (Jira/Slack/Bugsnag fetchers, sync wrappers, `AgentRuns::*`, the Slack review ping) — the file map, shape and checklist live in the `ai-worker-detached-agent-runs` skill; the Brainstorm subsystem (`app/services/brainstorm/**`, `BrainstormJob`) is in `ai-worker-brainstorm`.

**Jira worklogs** (REST with `JIRA_EMAIL` / `JIRA_ACCESS_TOKEN`: `Jira::WorklogClient`, `TimeLogger`, `TimeLogBatch`, `HoursSync`, `JiraHoursSyncJob`, `TimeLog`) — the file map, data flow and conventions live in the `ai-worker-jira-worklogs` skill.
- `app/jobs/application_job.rb` — Rails default base class.

## Conventions

- **Never build a shell command as a `cd X && ...` string.** Subprocesses use `Open3.capture3(*command, chdir: dir)` (Git/Github services) or `Process.spawn(..., chdir:)` with an argument array (agent runs: `ai-worker-agent-cli`). Never interpolate untrusted text (ticket text, Slack text, PR titles) into a shell string — pass it as an argument or in the prompt/env.
- Each service raises its own `CommandError` subclass on a non-zero exit instead of returning a boolean. The stage pipeline and sync jobs each handle their own typed failures; don't rescue inside the Git/Github/Runner objects.
- Agent runs are detached and polled across ticks; a job must never block on one (state and start/finish rules: `ai-worker-agent-cli`).
- Scheduler concurrency rules (per-clone, `MAX_CONCURRENT_AGENTS`, head-of-line, Sidekiq concurrency 1): see `ai-worker-scheduling`.
- Stage-pipeline `StageRun` logging and failure conventions: see `ai-worker-stage-pipeline`.
- Agents get the least tool access and secrets only as env vars: see `ai-worker-agent-cli`.
- Test with RSpec, not scratch runners. Put specs under `spec/services/**` or `spec/jobs/**` (stub `Open3`, `AiCli::Runner` and `Github::Client`, or use temp directories and temp git repos) and run `RAILS_ENV=test bundle exec rspec`. Never run scratch scripts, `bin/rails runner` or console code against the development DB, and never start a real agent against a real project to "try it".
