---
name: ai-worker-orchestration
description: Owns cross-cutting service and job conventions outside another subsystem. Use when adding an unowned service namespace or job, touching app/jobs/application_job.rb or config/initializers/sidekiq.rb, or changing shared subprocess and error rules.
---

# ai-worker-orchestration

Use this skill only for work without a specialised owner, the Rails job base / Sidekiq initializer, or conventions shared across service layers. The overall design is in `docs/ARCHITECTURE.md` and `docs/RUNBOOK.md`; where they and the code disagree, the code wins.

Path ownership is resolved by the first-match routing table in `ai-worker-review`; each owning skill's file map is authoritative for its paths.

## File map

- `app/jobs/application_job.rb` — Rails job base class shared by all Sidekiq jobs.
- `config/initializers/sidekiq.rb` — Sidekiq initializer wiring shared by the job runtime.

## Adding a new service/job

1. Pick the existing owning skill before creating files. If none fits, create the focused owning skill first; this skill then covers only the shared conventions and `ApplicationJob` / Sidekiq wiring.
2. Inject external collaborators as keyword arguments with production defaults, so specs can provide doubles.
3. Put its RSpec coverage under the matching `spec/services/<namespace>/` or `spec/jobs/` path and follow `ai-worker-testing`.
4. Add a routing row in `ai-worker-review` for the new namespace/job and its owning skill. For behaviour-preserving extraction or moves, follow `ai-worker-refactoring`; for detached agent fetch/sync work, follow `ai-worker-detached-agent-runs`.

## Conventions

- **Never build a shell command as a `cd X && ...` string.** Subprocesses use `Open3.capture3(*command, chdir: dir)` (Git/Github services) or `Process.spawn(..., chdir:)` with an argument array (agent runs: `ai-worker-agent-cli`). Never interpolate untrusted text (ticket text, Slack text, PR titles) into a shell string — pass it as an argument or in the prompt/env.
- Each service raises its own `CommandError` subclass on a non-zero exit instead of returning a boolean. The stage pipeline and sync jobs each handle their own typed failures; don't rescue inside the Git/Github/Runner objects.
- Agent runs are detached and polled across ticks; a job must never block on one (state and start/finish rules: `ai-worker-agent-cli`).
- Scheduler concurrency rules (per-clone, `MAX_CONCURRENT_AGENTS`, head-of-line, Sidekiq concurrency 1): see `ai-worker-scheduling`.
- Stage-pipeline `StageRun` logging and failure conventions: see `ai-worker-stage-pipeline`.
- Agents get the least tool access and secrets only as env vars: see `ai-worker-agent-cli`.
- Test with RSpec, not scratch runners. Put specs under `spec/services/**` or `spec/jobs/**` (stub `Open3`, `AiCli::Runner` and `Github::Client`, or use temp directories and temp git repos) and run `RAILS_ENV=test bundle exec rspec`. Never run scratch scripts, `bin/rails runner` or console code against the development DB, and never start a real agent against a real project to "try it".
