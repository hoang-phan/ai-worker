---
name: ai-worker-orchestration
description: Applies ai-worker's cross-cutting service/job conventions. Use when adding a new service namespace or job no existing skill owns, touching app/jobs/application_job.rb or config/initializers/sidekiq.rb, or changing shared subprocess/error conventions. Existing subsystem paths belong to their specialised skills.
---

# ai-worker-orchestration

Use this skill only for work without a specialised owner, the Rails job base / Sidekiq initializer, or conventions shared across service layers. The overall design is in `docs/ARCHITECTURE.md` and `docs/RUNBOOK.md`; where they and the code disagree, the code wins.

## File map

Each existing `app/services/**` and `app/jobs/**` path has one primary owner. Other narrowly scoped skills can still apply where their descriptions say so.

| Path glob | Owning skill |
| --- | --- |
| `app/jobs/application_job.rb` | `ai-worker-orchestration` |
| `app/jobs/brainstorm_job.rb`, `app/services/brainstorm/**` | `ai-worker-brainstorm` |
| `app/jobs/bugsnag_sync_job.rb`, `app/services/bugsnag/**` | `ai-worker-bugsnag-triage` |
| `app/jobs/jira_sync_job.rb`, `app/services/jira/{agent_fetcher,fetch_error,fetch_prompt,sync_cycle_source,ticket_importer,ticket_ref,ticket_rows,ticket_sync}.rb` | `ai-worker-jira-ticket-sync` |
| `app/jobs/jira_hours_sync_job.rb`, `app/services/jira/{hours_sync,http_transport,rest_client,time_log_batch,time_log_mirror,time_logger,time_slot_planner,worklog_client,worklog_error,worklog_site_sync,worklog_target}.rb` | `ai-worker-jira-worklogs` |
| `app/jobs/slack_review_job.rb`, `app/services/slack/{fetch_error,mention_fetcher,mention_prompt,mention_rows,review_candidate,review_cycle_source,review_importer,review_sync}.rb` | `ai-worker-pr-review-workflows` |
| `app/jobs/slack_ping_job.rb`, `app/services/slack/{notify_error,ping_collector,ping_run,review_message,review_notifier}.rb` | `ai-worker-slack-review-pings` |
| `app/jobs/workflow_scheduler_job.rb`, `app/services/scheduling/**` | `ai-worker-scheduling` |
| `app/services/agent_runs/**` | `ai-worker-detached-agent-runs` |
| `app/services/ai_cli/**`, `app/services/ci/**`, `app/services/stages/run_tooling.rb` | `ai-worker-agent-cli` |
| `app/services/{git,github}/**` | `ai-worker-git-github` |
| `app/services/prompts/**` | `ai-worker-prompts` |
| `app/services/stage_executor.rb`, `app/services/stages/**` except `run_tooling.rb` | `ai-worker-stage-pipeline` |

## Adding a new service/job

1. Pick the existing owning skill before creating files. If none fits, create the focused owning skill first; this skill then covers only the shared conventions and `ApplicationJob` / Sidekiq wiring.
2. Inject external collaborators as keyword arguments with production defaults, so specs can provide doubles.
3. Put its RSpec coverage under the matching `spec/services/<namespace>/` or `spec/jobs/` path and follow `ai-worker-testing`.
4. Update this file map with the new namespace/job and its owning skill. For behaviour-preserving extraction or moves, follow `ai-worker-refactoring`; for detached agent fetch/sync work, follow `ai-worker-detached-agent-runs`.

## Conventions

- **Never build a shell command as a `cd X && ...` string.** Subprocesses use `Open3.capture3(*command, chdir: dir)` (Git/Github services) or `Process.spawn(..., chdir:)` with an argument array (agent runs: `ai-worker-agent-cli`). Never interpolate untrusted text (ticket text, Slack text, PR titles) into a shell string — pass it as an argument or in the prompt/env.
- Each service raises its own `CommandError` subclass on a non-zero exit instead of returning a boolean. The stage pipeline and sync jobs each handle their own typed failures; don't rescue inside the Git/Github/Runner objects.
- Agent runs are detached and polled across ticks; a job must never block on one (state and start/finish rules: `ai-worker-agent-cli`).
- Scheduler concurrency rules (per-clone, `MAX_CONCURRENT_AGENTS`, head-of-line, Sidekiq concurrency 1): see `ai-worker-scheduling`.
- Stage-pipeline `StageRun` logging and failure conventions: see `ai-worker-stage-pipeline`.
- Agents get the least tool access and secrets only as env vars: see `ai-worker-agent-cli`.
- Test with RSpec, not scratch runners. Put specs under `spec/services/**` or `spec/jobs/**` (stub `Open3`, `AiCli::Runner` and `Github::Client`, or use temp directories and temp git repos) and run `RAILS_ENV=test bundle exec rspec`. Never run scratch scripts, `bin/rails runner` or console code against the development DB, and never start a real agent against a real project to "try it".
