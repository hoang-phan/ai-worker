---
name: ai-worker-detached-agent-runs
description: Checklist for adding or changing an agent-backed fetch/sync/triage service and its job — Jira::AgentFetcher, Slack::MentionFetcher, Bugsnag::Triager on AiCli::DetachedRun. Use when a task adds a new detached-agent service, changes its result file, prompt, tool allowlist, blockers, import, sync job or schedule.yml entry, or touches AiCli::DetachedRun or app/services/agent_runs/**.
---

# ai-worker-detached-agent-runs

Scope: the services that start the agent CLI detached, read a JSON array back from a result file, and import it into records. Shared subprocess/error conventions are in `ai-worker-orchestration`, the `AiCli` runner/poller layer under `DetachedRun` in `ai-worker-agent-cli`, spec rules in `ai-worker-testing`, model/migration rules in `ai-worker-domain` — not repeated here.

End-to-end Slack-driven reviews of someone else's PR: `ai-worker-pr-review-workflows`.

## Moving parts

- `app/services/ai_cli/detached_run.rb` — the shared state machine: `DetachedRun.new(dir:, result_name:, stale_after:, error_class:, runner: AiCli::Runner)` with `start(cwd:, prompt:, allowed_tools:, model:, effort:)`, `running?`, `poll { |rows| ... }`, `last_started_at`, `read_rows`, `log_path`, `result_path`. State dir holds `pid`, `started_at`, `agent.log` and the result file. `start` is a no-op (false) while the process is alive and deletes any old result; `poll` returns nil while running, raises `error_class` once running past `stale_after`, and after the process ends clears the pid and returns the (block-filtered) rows.
- **Result file contract**: a JSON array and nothing else. `[]` means "ran, nothing found". Missing file or invalid JSON / non-array raises the module's `FetchError`, so the prompt must say "if the lookup fails, do NOT create the file".
- **Fetcher** (`Jira::AgentFetcher`, `Slack::MentionFetcher`, `Bugsnag::Triager`) — only runs the agent: wraps one `DetachedRun` (memoised `run`), owns `ROOT = Rails.root.join("tmp", ...)`, `STALE_AFTER`, `ALLOWED_TOOLS` (where the run needs tools), the prompt, and a `poll` of the form `run.poll { |rows| XRows.call(rows) }`. The row parser is a pure object with no filesystem/DB access (`Bugsnag::TriageRows`, `Jira::TicketRows`, `Slack::MentionRows`) that drops malformed rows; free-text from the agent is validated there with a regex such as `Jira::TicketRef::KEY`/`ID`/`ReviewSync::PR_URL`. Test it directly, not through a fake pid/result file. Bugsnag's ledger merge is likewise pure (`Bugsnag::LedgerMerge`). Public surface: `running?`, `last_started_at`, `start`, `poll`.
- **`FetchError`** — one `class FetchError < StandardError` per module (`Jira::`, `Slack::`, `Bugsnag::`, `Brainstorm::`), each in its own `<module>/fetch_error.rb` (never inline in the fetcher), passed as `error_class`.
- **Sync wrapper** (`Jira::TicketSync`, `Slack::ReviewSync`, `Bugsnag::TriageSync`) — `blockers` (array of human-readable reasons it can't run), the fetcher (`fetcher`; `triager` for Bugsnag, memoised, injectable), and an idempotent `import(rows)` returning a `Result` struct with a `summary` (created/skipped/failed; for Bugsnag `added` keys after merging into `sync.ledger`).
- **Job** (`app/jobs/jira_sync_job.rb`, `slack_review_job.rb`, `bugsnag_sync_job.rb`) and its `config/schedule.yml` entries (`*/5` in working hours plus an hourly off-hours twin; queue `default`). The job's own throttle (`FETCH_EVERY`, `RUN_HOUR`) is separate from the cron cadence; the due logic lives in `AgentRuns::Cadence` (`every`, `daily_on_weekdays`), which the source's `due?` calls with those constants (`FETCH_EVERY`/`RUN_HOUR` live on the source; the job re-exports them).
- **Last-result recording**: `last_result` + `last_synced_at` on `JiraSync`/`BugsnagSync`, `slack_last_result` + `slack_last_synced_at` on `Project` (`db/schema.rb`). Errors are recorded as `"failed: #{e.message}".truncate(250)`.
- **Brainstorm** — different shape (Planner → RunLifecycle → RunOutcome, not fetcher + sync wrapper): see the `ai-worker-brainstorm` skill.
- **Jira** — ticket import (assigned tickets → development workflows): see the `ai-worker-jira-ticket-sync` skill.
- **Slack** — PR-review mention import: see the `ai-worker-pr-review-workflows` skill; outbound review pings: see the `ai-worker-slack-review-pings` skill.
- **Bugsnag** — file map, invariants and change checklist: see the `ai-worker-bugsnag-triage` skill.
- `app/services/agent_runs/sync_cycle.rb` — `AgentRuns::SyncCycle` performs one poll/import/start pass (`spec/services/agent_runs/sync_cycle_spec.rb`).
- `app/services/agent_runs/cycle_source.rb` — `AgentRuns::CycleSource` defines source defaults and hooks (`spec/services/agent_runs/sync_cycle_spec.rb`).
- `app/services/agent_runs/fetcher_cycle_source.rb` — `AgentRuns::FetcherCycleSource` adapts a fetcher and sync wrapper (`spec/services/agent_runs/fetcher_cycle_source_spec.rb`).
- `app/services/agent_runs/cadence.rb` — `AgentRuns::Cadence` supplies pure due-time rules (`spec/services/agent_runs/cadence_spec.rb`).
- `app/services/agent_runs/manual_start.rb` — `AgentRuns::ManualStart` implements the manual-run result flow (`spec/services/agent_runs/manual_start_spec.rb`).
- **Job behaviour**: each sync job imports a finished result first, then starts a new run only if none is running and its trigger rule holds (last fetch old enough for Jira/Slack, once per weekday after a set hour for Bugsnag, no pending workflow for brainstorm); fetch errors are logged and recorded on the sync/project as its "last result".

## Checklist for a new one

1. Domain first (`ai-worker-domain`): migration + model fields for the trigger/last-result columns (and a ledger if you need cross-run dedupe); add any new `StageRun` action to `StageRun::ACTIONS` before anything logs it.
2. Fetcher: `x/fetch_error.rb` (`module X; class FetchError < StandardError; end`), `ROOT` under `tmp/<name>`, `STALE_AFTER` (15 min for lookups, 45 for runs that read code), constructor `initialize(record, root: ROOT, run: nil)` building the default `AiCli::DetachedRun.new(...)` from `root`, `delegate :running?, :last_started_at, to: :run`, `start`/`poll` calling it, `filter` for the row shape.
3. Least privilege: pass an `ALLOWED_TOOLS` array with only the read/search tools the run needs plus `Write` for the result file. Nothing that posts, reacts, transitions or edits unless the feature is exactly that (Bugsnag's `createJiraIssue`/`editJiraIssue` are the only writes). Access goes through the agent's MCP connectors — never add tokens to the app.
4. Prompt: say what is read-only, spell out the absolute result path (`run.result_path`, never re-derive `dir.join("<name>.json")`), give an example row, say `[]` for none and "do NOT create the file if the lookup fails", ask for one short reply line. User free text (assignee, mention, project) is passed as data for the agent to resolve; never interpolate it into a shell string, and never put secrets in it.
5. Sync wrapper: `blockers` listing every missing precondition, `fetcher`, idempotent `import` (skip what already exists, one failed row must not stop the rest).
6. Source + job: a fetcher-backed source subclasses `AgentRuns::FetcherCycleSource`, passes its injected/default sync wrapper and fetcher to `super`, and keeps only record-specific persistence, eligibility, cadence, and hooks; use plain doubles to cover the shared plumbing in `spec/services/agent_runs/fetcher_cycle_source_spec.rb`. A planner-shaped source such as Brainstorm may subclass `CycleSource` directly. The source declares `RESCUE_ERRORS = [ X::FetchError, AiCli::CommandError ].freeze` and overrides `rescue_errors` to return it (the `CycleSource` default is `[ AiCli::CommandError ]`); a manual-run controller reuses `X::SyncCycleSource::RESCUE_ERRORS` for `start_manually`. The job is just `find_each` + `AgentRuns::SyncCycle.call(source: X.new(record), log_prefix:)` — `SyncCycle` defaults `rescue_errors:` to `source.rescue_errors` (pass it only to override). `SyncCycle` runs, in this order: poll → `import` + record if rows came back; then skip if `fetcher.running?` or your trigger rule says not yet; then `blockers` (log a warning, don't start) else `fetcher.start`. The source's `rescue_errors` are rescued per record and the failure is written to last-result. Never wait on the agent.
7. `config/schedule.yml`: working-hours entry + off-hours entry on `queue: default`; keep `config/sidekiq.yml` concurrency untouched.
8. Add the service to "Moving parts" above and to `ai-worker-orchestration`'s File map under this skill; if the UI shows last-result, handle it via `ai-worker-ui`.

## Spec recipe

- `spec/services/ai_cli/detached_run_spec.rb` is the model: `let_tmpdir` state dir, pass a fake `runner:` (`instance_double`; `start` returns `4242`, `poll` returns `:running` or `[ :completed, nil ]`), write a fake `pid` and result file by hand, then call `poll`.
- Brainstorm specs: see `ai-worker-brainstorm`.
- Fetcher specs (`spec/services/{jira,slack,bugsnag}/*_spec.rb`): pass `root: Pathname(tmp)` (no `stub_const`); for `start`/`poll` pass a fake `run:` that records `start`'s kwargs and assert cwd, allowed_tools and the result file named in the prompt, write a result file with good and junk rows, assert `poll` returns only the filtered rows; also cover missing file, bad JSON, non-array, and staleness (pid alive and `started_at` older than `STALE_AFTER` raises `FetchError` and clears the pid).
- Sync specs: each `blockers` reason, `import` creating records, idempotent re-import, a row that fails validation landing in `failed`.
- Job specs (`spec/jobs/*_sync_job_spec.rb`): stub `AgentRuns::SyncCycle.call`; assert the job's record selection plus one exact call per selected record (the wrapping source class and log prefix; no `rescue_errors:` — that default is covered by the source spec asserting `rescue_errors` returns `RESCUE_ERRORS`, and real-cycle doubles stub `rescue_errors: X::RESCUE_ERRORS`), and only retain one thin real-cycle example that an expected error is recorded as `"failed: ..."` while the next record runs. Keep cadence, blockers, import/start ordering, summaries, and source persistence in the `AgentRuns` and source/sync specs.
- Run with `RAILS_ENV=test bundle exec rspec`.

## Safety

- No secrets in prompts, logs or result files; the app holds no Jira/Slack/Bugsnag tokens.
- Never start a real agent (or call `fetcher.start`) against a real project to try it — pass a fake `runner:`. No scratch scripts or `rails runner` against the development DB; every command sets `RAILS_ENV=test`.
- Don't delete or hand-edit real `tmp/<name>/<id>` state dirs; a stale pid is cleared by `poll`.
