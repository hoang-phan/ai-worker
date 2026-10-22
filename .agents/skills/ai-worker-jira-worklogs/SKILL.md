---
name: ai-worker-jira-worklogs
description: Applies ai-worker's Jira worklog / time-logging discipline. Use for any task touching app/services/jira/{worklog_client,worklog_target,time_logger,time_log_batch,time_slot_planner,hours_sync}.rb, app/jobs/jira_hours_sync_job.rb, app/models/time_log.rb, WorkflowTimeLogsController, or the log-time buttons in the project/workflow views.
---

# ai-worker Jira worklogs

A separate subsystem from the agent-backed Jira fetchers: it talks to Jira Cloud over plain REST (`Net::HTTP`) with `JIRA_EMAIL` / `JIRA_ACCESS_TOKEN` env vars, not through the agent/MCP (see `ai-worker-detached-agent-runs` for that side).

## File map

- `app/services/jira/worklog_client.rb` — `Jira::WorklogClient.new(base_url)`: `add_worklog(key, started_at:, seconds:)` (returns the worklog id), `set_original_estimate_if_blank(key, seconds)` (true if it updated), `my_worklogs(key)` (the credentials' user's worklogs, matched on accountId: `[{ id:, started:, seconds: }]`), `keys_with_my_worklogs_since(date)` (JQL search, includes tickets the app doesn't know). Its private `request` helper builds/authenticates requests, checks status, parses JSON, and maps errors.
- `app/services/jira/http_transport.rb` — `Jira::HttpTransport#call(request, uri)` performs the `Net::HTTP` round trip with Jira's five-second open and 15-second read timeouts. Inject it into `WorklogClient` specs instead of globally stubbing `Net::HTTP`.
- `app/services/jira/worklog_error.rb` — `Jira::WorklogError`, the only error type of this subsystem.
- `app/services/jira/worklog_target.rb` — `WorklogTarget.new(workflow)`: `base_url`, `key`, and `problem` (nil, or why the workflow can't log time: not a Jira-kind project + development workflow, no site URL, no ticket key). Pure value object. Ticket keys come from `Jira::TicketRef`.
- `app/services/jira/time_logger.rb` — `TimeLogger#log(workflow, hours)`; `PRESET_HOURS` (0.5/1/1.5/2) feeds the controller and views.
- `app/services/jira/time_slot_planner.rb` — `TimeSlotPlanner#next_start(seconds)`: first weekday of the current month under `DAILY_TARGET` (6 h) across all `time_logs`, at a free whole hour between 6 and 17.
- `app/services/jira/time_log_batch.rb` — `TimeLogBatch#call(workflows, hours)` returns a `Result` (`logged`, `failure`, `success?`, `message(hours)`).
- `app/services/jira/hours_sync.rb` — `HoursSync#call` (every ticket of the development workflows of Jira projects, plus this month's logged tickets) and `#recent(base_url)` (this month's only); returns `Result(synced:, failed:)`.
- `app/jobs/jira_hours_sync_job.rb` — runs `HoursSync#call`; scheduled twice in `config/schedule.yml` (`jira_hours_sync`, `jira_hours_sync_off_hours`). Failed tickets and `WorklogError` are only logged.
- `app/models/time_log.rb` — mirror row (`ticket_key`, `started_at`, `seconds`, `jira_worklog_id`, optional `workflow`); `Workflow#logged_seconds` and `ProjectsController#show` sum it.
- Entry point: `WorkflowTimeLogsController#create` (routed as `post :log_time, on: :collection, to: "workflow_time_logs#create"`, helper `log_time_project_workflows_path`), driven by the batch bars in `app/views/projects/show.html.erb` and `app/views/workflows/_details.html.erb`. It validates hours against `PRESET_HOURS`, then calls `TimeLogBatch`.
- Specs: `spec/services/jira/{worklog_client,time_logger,time_log_batch,time_slot_planner,hours_sync}_spec.rb`, `spec/jobs/jira_hours_sync_job_spec.rb`, plus `spec/requests/{workflows,projects}_spec.rb`.

## Data flow

- Jira is the source of truth. `HoursSync` mirrors the user's worklogs into `time_logs`: per ticket, rows missing from Jira are deleted and the rest are matched by `jira_worklog_id` (find-or-initialize, then update). A failed ticket keeps its old rows and goes in `failed`; `jira_logged_synced_at` is stamped on the workflows that synced.
- `TimeLogBatch` calls `hours_sync.recent` per Jira site first (so days filled elsewhere aren't topped up), then `TimeLogger#log` for each workflow in order, stopping at the first `WorklogError` and reporting what was already logged.
- `TimeLogger` creates the Jira worklog first, then the `TimeLog` row (a failed Jira call leaves no phantom time), then sets the original estimate when blank/0. The estimate step is best effort: a `WorklogError` there is logged and swallowed.

## Conventions

- Never call Jira from specs. Inject the `client_factory:` lambda (`TimeLogger`, `HoursSync`) or `WorklogClient`'s `transport:` (client spec). Stub `Net::HTTP.start` only in `HttpTransport` specs.
- Missing `JIRA_EMAIL` / `JIRA_ACCESS_TOKEN` abort: the client raises `WorklogError` ("... are not set") and `HoursSync` re-raises it instead of recording it per ticket.
- `Jira::WorklogError` is the only error type: map transport/HTTP/JSON failures to it in the client; callers rescue only it.
- No code in this subsystem writes `time_logs` except `TimeLogger` (new worklog) and `HoursSync` (mirror).
