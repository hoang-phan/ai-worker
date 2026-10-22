---
name: ai-worker-detached-agent-runs
description: Checklist for adding or changing an agent-backed fetch/sync/triage service and its job — Jira::AgentFetcher, Slack::MentionFetcher, Bugsnag::Triager on AiCli::DetachedRun. Use when a task adds a new detached-agent service, changes its result file, prompt, tool allowlist, blockers, import, sync job or schedule.yml entry, or touches AiCli::DetachedRun.
---

# ai-worker-detached-agent-runs

Scope: the services that start the agent CLI detached, read a JSON array back from a result file, and import it into records. General job/service rules are in `ai-worker-orchestration`, spec rules in `ai-worker-testing`, model/migration rules in `ai-worker-domain` — not repeated here.

## Moving parts

- `app/services/ai_cli/detached_run.rb` — the shared state machine: `DetachedRun.new(dir:, result_name:, stale_after:, error_class:)` with `start(cwd:, prompt:, allowed_tools:, model:, effort:)`, `running?`, `poll { |rows| ... }`, `last_started_at`, `read_rows`, `log_path`. State dir holds `pid`, `started_at`, `agent.log` and the result file. `start` is a no-op (false) while the process is alive and deletes any old result; `poll` returns nil while running, raises `error_class` once running past `stale_after`, and after the process ends clears the pid and returns the (block-filtered) rows.
- **Result file contract**: a JSON array and nothing else. `[]` means "ran, nothing found". Missing file or invalid JSON / non-array raises the module's `FetchError`, so the prompt must say "if the lookup fails, do NOT create the file".
- **Fetcher** (`Jira::AgentFetcher`, `Slack::MentionFetcher`, `Bugsnag::Triager`) — wraps one `DetachedRun` (memoised `run`), owns `ROOT = Rails.root.join("tmp", ...)`, `STALE_AFTER`, `ALLOWED_TOOLS` (where the run needs tools), the prompt, and a `poll` of the form `run.poll { |rows| XRows.call(rows) }`. The row parser is a pure object with no filesystem/DB access (`Bugsnag::TriageRows`, `Jira::TicketRows`, `Slack::MentionRows`) that drops malformed rows; free-text from the agent is validated there with a regex such as `KEY`/`ID`/`ReviewSync::PR_URL`. Test it directly, not through a fake pid/result file. Bugsnag's ledger merge is likewise pure (`Bugsnag::LedgerMerge`). Public surface: `running?`, `last_started_at`, `start`, `poll`.
- **`FetchError`** — one `class FetchError < StandardError` per module (`Jira::`, `Slack::`, `Bugsnag::`, `Brainstorm::`), passed as `error_class`.
- **Sync wrapper** (`Jira::TicketSync`, `Slack::ReviewSync`; `Bugsnag::Triager` plays both roles) — `blockers` (array of human-readable reasons it can't run), `fetcher`, and an idempotent `import(rows)` returning a `Result` struct (created/skipped/failed) or, for Bugsnag, merging into `sync.ledger`.
- **Job** (`app/jobs/jira_sync_job.rb`, `slack_review_job.rb`, `bugsnag_sync_job.rb`) and its `config/schedule.yml` entries (`*/5` in working hours plus an hourly off-hours twin; queue `default`). The job's own throttle (`FETCH_EVERY`, `RUN_HOUR`) is separate from the cron cadence; the due logic lives in `AgentRuns::Cadence` (`every`, `daily_on_weekdays`), which the job's `due:` callback calls with those constants.
- **Last-result recording**: `last_result` + `last_synced_at` on `JiraSync`/`BugsnagSync`, `slack_last_result` + `slack_last_synced_at` on `Project` (`db/schema.rb`). Errors are recorded as `"failed: #{e.message}".truncate(250)`.
- `Brainstorm::Planner` already builds its `run` on `DetachedRun` but still has its own `pid_file`/`poll` and `Result`; treat `DetachedRun` as the target shape and finish that migration rather than copying the planner's local state handling.

## Checklist for a new one

1. Domain first (`ai-worker-domain`): migration + model fields for the trigger/last-result columns (and a ledger if you need cross-run dedupe); add any new `StageRun` action to `StageRun::ACTIONS` before anything logs it.
2. Fetcher: `module X; class FetchError`, `ROOT` under `tmp/<name>`, `STALE_AFTER` (15 min for lookups, 45 for runs that read code), `run` = `AiCli::DetachedRun.new(...)`, `start`/`poll`/`running?`/`last_started_at` delegating to it, `filter` for the row shape.
3. Least privilege: pass an `ALLOWED_TOOLS` array with only the read/search tools the run needs plus `Write` for the result file. Nothing that posts, reacts, transitions or edits unless the feature is exactly that (Bugsnag's `createJiraIssue`/`editJiraIssue` are the only writes). Access goes through the agent's MCP connectors — never add tokens to the app.
4. Prompt: say what is read-only, spell out the absolute result path (`dir.join("<name>.json")`), give an example row, say `[]` for none and "do NOT create the file if the lookup fails", ask for one short reply line. User free text (assignee, mention, project) is passed as data for the agent to resolve; never interpolate it into a shell string, and never put secrets in it.
5. Sync wrapper: `blockers` listing every missing precondition, `fetcher`, idempotent `import` (skip what already exists, one failed row must not stop the rest).
6. Job, in this order: poll → `import` + record if rows came back; then skip if `fetcher.running?` or your trigger rule says not yet; then `blockers` (log a warning, don't start) else `fetcher.start`. Rescue `Module::FetchError, AiCli::CommandError` per record and write the failure to last-result. Never wait on the agent.
7. `config/schedule.yml`: working-hours entry + off-hours entry on `queue: default`; keep `config/sidekiq.yml` concurrency untouched.
8. Add the service to the "Detached-agent sync services" map in `ai-worker-orchestration` and, if the UI shows last-result, handle it via `ai-worker-ui`.

## Spec recipe

- `spec/services/ai_cli/detached_run_spec.rb` is the model: `Dir.mktmpdir` state dir, `allow(AiCli::Runner).to receive(:start).and_return(4242)`, `allow(AiCli::Runner).to receive(:poll).and_return(:running)` or `[ :completed, nil ]`, write a fake `pid` and result file by hand, then call `poll`.
- Fetcher specs (`spec/services/{jira,slack,bugsnag}/*_spec.rb`): `stub_const("X::ROOT", Pathname(tmp))`, write a result file with good and junk rows, assert `poll` returns only the filtered rows; also cover missing file, bad JSON, non-array, and staleness (pid alive and `started_at` older than `STALE_AFTER` raises `FetchError` and clears the pid).
- Sync specs: each `blockers` reason, `import` creating records, idempotent re-import, a row that fails validation landing in `failed`.
- Job specs (`spec/jobs/*_sync_job_spec.rb`): stub the fetcher; assert import-before-start, no start while running or blocked, FetchError recorded as `"failed: ..."`.
- Run with `RAILS_ENV=test bundle exec rspec`.

## Safety

- No secrets in prompts, logs or result files; the app holds no Jira/Slack/Bugsnag tokens.
- Never start a real agent (or call `fetcher.start`) against a real project to try it — stub `AiCli::Runner`. No scratch scripts or `rails runner` against the development DB; every command sets `RAILS_ENV=test`.
- Don't delete or hand-edit real `tmp/<name>/<id>` state dirs; a stale pid is cleared by `poll`.
