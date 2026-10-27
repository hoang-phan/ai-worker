---
name: ai-worker-jira-worklogs
description: Applies ai-worker's Jira worklog / time-logging discipline. Use for any task touching app/services/jira/{worklog_target,time_logger,time_log_batch,time_log_mirror,time_slot_planner,hours_sync,worklog_site_sync}.rb, app/jobs/jira_hours_sync_job.rb, app/models/time_log.rb, WorkflowTimeLogsController, or the log-time buttons in the project/workflow views.
---

# ai-worker Jira worklogs

A separate subsystem from the agent-backed Jira fetchers. Its external Jira Cloud REST implementation is owned by `ai-worker-jira-rest-client`; it uses `JIRA_EMAIL` / `JIRA_ACCESS_TOKEN`, not the agent/MCP (see `ai-worker-detached-agent-runs` for that side).

## File map

- External-client pointer: `ai-worker-jira-rest-client` owns `Jira::WorklogClient`, `Jira::RestClient`, `Jira::HttpTransport`, and `Jira::WorklogError`, including their direct specs, REST/authentication/pagination contracts, and Jira request errors.
- `app/services/jira/worklog_target.rb` — `WorklogTarget.new(workflow)`: `base_url`, `key`, and `problem` (nil, or why the workflow can't log time: not a Jira-kind project + development workflow, no site URL, no ticket key). Pure value object. Ticket keys come from `Jira::TicketRef`.
- `app/services/jira/time_logger.rb` — `TimeLogger#log(workflow, hours)`; `PRESET_HOURS` (0.5/1/1.5/2) feeds the controller and views.
- `app/services/jira/time_slot_planner.rb` — `TimeSlotPlanner#next_start(seconds)`: first weekday of the current month under `DAILY_TARGET` (6 h) across all `time_logs`, at a free whole hour between 6 and 17. Its `logs:` collaborator defaults to the `TimeLog` query and can be injected for isolated slot-picking specs.
- `app/services/jira/time_log_batch.rb` — `TimeLogBatch#call(workflows, hours)` returns a `Result` (`logged`, `failure`, `success?`, `message(hours)`).
- `app/services/jira/time_log_mirror.rb` — `Jira::TimeLogMirror` upserts and removes mirrored worklogs for one ticket; `WorklogSiteSync` uses it (`spec/services/jira/time_log_mirror_spec.rb`).
- `app/services/jira/worklog_site_sync.rb` — `WorklogSiteSync.new(client:, mirror: TimeLogMirror.new, clock: -> { Time.current })#call(workflows, keys)`: syncs one site's ticket keys (deduped, first-seen order), records per-ticket `WorklogError` failures, stamps successful workflows' `jira_logged_synced_at` via `clock`. Duplicate ticket keys keep the last workflow (`index_by`). Returns `HoursSync::Result`.
- `app/services/jira/hours_sync.rb` — `HoursSync#call` (every ticket of the development workflows of Jira projects, plus this month's logged tickets) and `#recent(base_url)` (this month's only, empty workflows so nothing is stamped); discovers sites/workflows, reuses one client per site, delegates to `WorklogSiteSync`, aggregates `Result(synced:, failed:)`. Constructor: `client_factory:`, `today:`.
- `app/jobs/jira_hours_sync_job.rb` — `perform(sync: Jira::HoursSync.new)` runs `sync.call`; scheduled twice in `config/schedule.yml` (`jira_hours_sync`, `jira_hours_sync_off_hours`). Failed tickets and `WorklogError` are only logged; specs pass `sync:`.
- `app/models/time_log.rb` — mirror row (`ticket_key`, `started_at`, `seconds`, `jira_worklog_id`, optional `workflow`); `Workflow#logged_seconds` and `ProjectsController#show` sum it.
- `app/helpers/time_logs_helper.rb` — formats logged Jira hours, sync phrases, badges, and select-all checkbox data for time-log views.
- Entry point: `WorkflowTimeLogsController#create` (routed as `post :log_time, on: :collection, to: "workflow_time_logs#create"`, helper `log_time_project_workflows_path`), driven by the batch bars in `app/views/projects/show.html.erb` and `app/views/workflows/_details.html.erb`. It validates hours against `PRESET_HOURS`, then calls `TimeLogBatch`.
- Specs: `spec/services/jira/{time_logger,time_log_batch,time_log_mirror,time_slot_planner,hours_sync,worklog_site_sync}_spec.rb`, `spec/jobs/jira_hours_sync_job_spec.rb`, plus `spec/requests/{workflows,projects}_spec.rb`. Direct client specs belong to `ai-worker-jira-rest-client`; pipeline specs use injected clients and do not re-test REST plumbing.

## Data flow

- Jira is the source of truth. `HoursSync` discovers sites and keys; `WorklogSiteSync` mirrors each ticket via `TimeLogMirror` (rows missing from Jira are deleted; the rest match by `jira_worklog_id`). A failed ticket keeps its old rows and goes in `failed`; `jira_logged_synced_at` is stamped on the workflows that synced.
- `TimeLogBatch` calls `hours_sync.recent` per Jira site first (so days filled elsewhere aren't topped up), then `TimeLogger#log` for each workflow in order, stopping at the first `WorklogError` and reporting what was already logged.
- `TimeLogger` creates the Jira worklog first, then the `TimeLog` row (a failed Jira call leaves no phantom time), then sets the original estimate when blank/0. The estimate step is best effort: a `WorklogError` there is logged and swallowed.

## Conventions

- Never call Jira from specs. Inject the `client_factory:` lambda (`TimeLogger`, `HoursSync`) or `WorklogSiteSync`'s `client:` / `mirror:` / `clock:`. Client transport seams and `Net::HTTP` coverage belong to `ai-worker-jira-rest-client`.
- Missing `JIRA_EMAIL` / `JIRA_ACCESS_TOKEN` abort: the client raises `WorklogError` (`reason: :missing_credentials`) and `WorklogSiteSync` re-raises it instead of recording it per ticket.
- `Jira::WorklogError` is the only error type callers rescue; client-side failure mapping belongs to `ai-worker-jira-rest-client`.
- No code in this subsystem writes `time_logs` except `TimeLogger` (new worklog) and `TimeLogMirror` (via `WorklogSiteSync`).

## Spec recipe

- Injection seams — use them in specs instead of `stub_const` or `allow(X).to receive(:new)`: `HoursSync.new(client_factory:, today:)`, `WorklogSiteSync.new(client:, mirror:, clock:)`, `TimeLogger.new(client_factory:, planner:)`, `TimeSlotPlanner.new(today:, random:, logs:)`, `JiraHoursSyncJob.perform_now(sync:)`. REST client seams are documented by `ai-worker-jira-rest-client`.
- `spec/services/jira/worklog_site_sync_spec.rb`: `instance_double` for `client` / `mirror` / workflow, a fixed `clock:`; cover key uniq/order, last-wins duplicate keys, ordinary vs `missing_credentials?` errors, empty-workflows sync (no stamps).
- `spec/services/jira/hours_sync_spec.rb`: discovery (sites, recent keys without workflows), client reuse, cross-site aggregation, `#recent` not stamping unrelated workflows, plus one thin real-`TimeLogMirror` integration example. Per-ticket failure/stamping behaviour lives in `worklog_site_sync_spec`.
- `spec/services/jira/time_log_mirror_spec.rb` keeps persistence coverage (upsert, delete-gone, workflow attach-once).
- Run with `RAILS_ENV=test bundle exec rspec spec/services/jira spec/jobs/jira_hours_sync_job_spec.rb spec/requests/workflow_time_logs_spec.rb`.
