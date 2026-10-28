---
name: ai-worker-bugsnag-triage
description: Owns Bugsnag to Jira detached-agent triage and sync. Use for app/models/bugsnag_sync.rb, app/services/bugsnag/**, app/jobs/bugsnag_sync_job.rb, Bugsnag sync controllers and views, or bugsnag_sync scheduling.
---

# ai-worker-bugsnag-triage

Scope: a detached agent reads open Bugsnag errors, files a Jira Bug per new error, investigates the local clone read-only and writes cause/fix into the ticket; the app only records which errors were ticketed. Generic rules are not repeated: shared fetcher/sync/job shape and `AgentRuns::*` in `ai-worker-detached-agent-runs`, `DetachedRun`/runner in `ai-worker-agent-cli`, model/migration rules in `ai-worker-domain`, controllers/views in `ai-worker-ui`, specs in `ai-worker-testing`.

## File map (spec in parentheses)

- `app/models/bugsnag_sync.rb` — belongs_to project; `bugsnag_project`, `jira_project` (free text the agent resolves; required), `min_events` (default 5), `max_tickets` (default 3) positive integers, `auto_sync` (scope `auto`), `ledger` JSON `{ bugsnag_id => jira_key }`, `last_synced_at`, `last_result`; `label` = "bugsnag → jira" (`spec/models/bugsnag_sync_spec.rb`).
- `app/services/bugsnag/triager.rb` — starts/polls the one `DetachedRun` (`ROOT` tmp/bugsnag_syncs/<id>, `STALE_AFTER` 45 min, `ALLOWED_TOOLS`, cwd = project local clone) (`triager_spec.rb`).
- `app/services/bugsnag/triage_sync.rb` — `blockers` (`jira_kind`, `jira_site_url`, `local_directory`), memoised injectable `triager`, `import(rows)` → `Result(added)` with `summary` ("N new ticket(s): KEYS" / "nothing new") (`triage_sync_spec.rb`).
- `app/services/bugsnag/triage_rows.rb` — pure; keeps Hash rows whose `bugsnag_id` matches `ID` and `jira_key` is a Jira key (`triage_rows_spec.rb`).
- `app/services/bugsnag/ledger_merge.rb` — pure; `[new_ledger, added_keys]` (`ledger_merge_spec.rb`).
- `app/services/bugsnag/triage_prompt.rb` — pure prompt text from plain values (`triage_prompt_spec.rb`).
- `app/services/bugsnag/fetch_error.rb` — `Bugsnag::FetchError`, passed as `DetachedRun` `error_class` (covered via `triager_spec.rb`).
- `app/services/bugsnag/sync_cycle_source.rb` — `AgentRuns::CycleSource` adapter: `RUN_HOUR = 9`, `eligible?` = `auto_sync?`, `due?` = `AgentRuns::Cadence.daily_on_weekdays` (weekdays only, at/after 9 AM app time, none started yet today); `persist!` writes `last_synced_at` + `last_result` (`sync_cycle_source_spec.rb`).
- `app/jobs/bugsnag_sync_job.rb` — `find_each` + `AgentRuns::SyncCycle.call` rescuing `Bugsnag::FetchError, AiCli::CommandError` (`spec/jobs/bugsnag_sync_job_spec.rb`).
- `config/schedule.yml` — `bugsnag_sync` (`*/5` 05–13 Asia/Ho_Chi_Minh) and `bugsnag_sync_off_hours` (hourly otherwise), queue `default`; cron is only the poll tick, the once-a-day rule lives in the source.
- `app/controllers/bugsnag_syncs_controller.rb` — includes `ProjectScoped` then `ProjectChildCrud`, configuring `:bugsnag_syncs` and the "Bugsnag sync" flash label; CRUD remains nested under project (redirects to project; permits the five editable fields) (`spec/requests/bugsnag_syncs_spec.rb`).
- `app/controllers/bugsnag_sync_runs_controller.rb` — "Run now" (`POST /projects/:id/bugsnag_syncs/:id/run` → `#create`): one `ManualStartFlash#start_source_manually` call with `Bugsnag::SyncCycleSource` (`spec/requests/bugsnag_sync_runs_spec.rb`). Ignores `auto_sync`/`due?`.
- `app/views/bugsnag_syncs/{new,edit,_form,_list}.html.erb` (table: label, auto, ledger size, last run/result, Run now/Edit/Delete) — covered by the request specs.

## Invariants

- Result file is a JSON array only; `[]` means "ran, nothing found". On any Bugsnag/Jira failure the agent must NOT create the file (missing file ⇒ `FetchError`); the prompt rewrites it after each created ticket so a crash keeps them.
- `LedgerMerge` is idempotent: known ids and repeated ids keep their first key and add nothing; input ledger is never mutated; `import` only updates `ledger`.
- No Bugsnag/Jira tokens in the app: access is via the agent's MCP connectors. The only Jira writes allowed are `createJiraIssue`/`editJiraIssue`; no transition/assign/comment, no Bash/Edit, nothing changed in Bugsnag, code read-only (`Read/Grep/Glob` + `Write` for the result).
- Errors are recorded as `"failed: #{e.message}".truncate(250)` in `last_result` (done by `SyncCycle`); the job never waits on the agent.
- `TriageRows`/`LedgerMerge`/`TriagePrompt` stay pure (no DB/filesystem); free text from the agent is validated in `TriageRows`, never interpolated into a shell string.

## Change checklist

- New field on a triage row: `TriageRows` (validation + spec) → `TriagePrompt` example/instruction (+ spec) → `LedgerMerge`/`Bugsnag::TriageSync#import` if it is stored → ledger shape is `{ id => key }`, so a richer value needs a migration plan (`ai-worker-domain`).
- New `BugsnagSync` column: migration + `db/schema.rb`, controller permit list, `_form`, `_list` table, `TriagePrompt` args via `Bugsnag::Triager#prompt`, specs for each.
- Changing the prompt: keep the "do NOT create the file on failure" and `[]` lines, the absolute `run.result_path`, and the write limits; update `triage_prompt_spec.rb`. Widening `ALLOWED_TOOLS` needs a reason and a `triager_spec.rb` change.
- Changing the cadence: `RUN_HOUR` / `Cadence` rule in `SyncCycleSource`, the "Weekdays 9 AM" text in `_list.html.erb`, schedule hours if the window no longer covers it, and the comment in `BugsnagSyncJob`.
- Changing blockers: `Bugsnag::TriageSync#blockers` + `Projects::RunBlockers` message keys and `triage_sync_spec.rb`.

## Verify

`RAILS_ENV=test bundle exec rspec spec/services/bugsnag spec/jobs/bugsnag_sync_job_spec.rb spec/models/bugsnag_sync_spec.rb spec/requests/bugsnag_syncs_spec.rb spec/requests/bugsnag_sync_runs_spec.rb`; add `spec/services/agent_runs` when touching cadence or manual start. Never start a real agent or run scratch code against the development DB.
