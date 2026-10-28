---
name: ai-worker-jira-ticket-sync
description: Applies ai-worker's Jira ticket import discipline (agent fetches assigned tickets through the Atlassian MCP, app creates development workflows). Use for any task touching app/models/jira_sync.rb, app/services/jira/{agent_fetcher,fetch_prompt,ticket_rows,ticket_ref,ticket_sync,ticket_importer,fetch_error,sync_cycle_source}.rb, app/jobs/jira_sync_job.rb, the jira_sync entries in config/schedule.yml, app/controllers/jira_syncs_controller.rb, app/controllers/jira_sync_runs_controller.rb, app/views/jira_syncs/**, or their specs. Worklogs / time logging belong to ai-worker-jira-worklogs.
---

# ai-worker-jira-ticket-sync

Generic detached-run rules: `ai-worker-detached-agent-runs`; model/migrations: `ai-worker-domain`; controllers/views: `ai-worker-ui`; specs: `ai-worker-testing`. Not repeated here.

## Flow

`JiraSyncJob` (skips projects that aren't `jira_site?`) → `AgentRuns::SyncCycle` with `Jira::SyncCycleSource` → poll `AgentFetcher` → `TicketSync#import` → `TicketImporter` creates workflows; then starts a new fetch if idle and due.

## File map (file — role; spec)

- `app/models/jira_sync.rb` — one query per row, `belongs_to :project`: free-text `jira_project` and/or `parent_ticket` (both optional, the agent resolves them), `auto_sync`, `last_result`, `last_synced_at`; `auto` scope, `label`; `spec/models/jira_sync_spec.rb`.
- `app/services/jira/agent_fetcher.rb` — wraps `AiCli::DetachedRun` (`tmp/jira_sync/<id>/tickets.json`, `STALE_AFTER` 15 min); `spec/services/jira/agent_fetcher_spec.rb`.
- `app/services/jira/fetch_prompt.rb` — pure prompt (read-only, "To Do", assignee/project/parent as data, `[]` for none, no file on failure); `fetch_prompt_spec.rb`.
- `app/services/jira/ticket_rows.rb` — pure filter of `tickets.json` rows to `{"key","summary"}`; drops non-hashes and invalid keys; `ticket_rows_spec.rb`.
- `app/services/jira/ticket_ref.rb` — `KEY_PATTERN`/`KEY` regex, `key?`, `key_for(jira_ticket)` (used by `Workflow#jira_key`, so worklogs depend on it), `branch_name_for`, `url_for`; `ticket_ref_spec.rb`.
- `app/services/jira/ticket_sync.rb` — `blockers` (via `Projects::RunBlockers`: jira_kind, jira_site_url, assignee, default_reviewers), memoised injectable `fetcher`, `import(issues)`, and `Result` aliasing `AgentRuns::ImportResult` (blockers/created/skipped/failed, `summary`); `ticket_sync_spec.rb`.
- `app/services/jira/ticket_importer.rb` — per-issue import (below); `ticket_importer_spec.rb`.
- `app/services/jira/fetch_error.rb` — `Jira::FetchError`, passed as `error_class`; no own spec.
- `app/services/jira/sync_cycle_source.rb` — `AgentRuns::CycleSource` subclass; `FETCH_EVERY = 3.hours` via `AgentRuns::Cadence.every`; `eligible?` = `auto_sync?`; persists `last_result`/`last_synced_at`; `sync_cycle_source_spec.rb`.
- `app/jobs/jira_sync_job.rb` — iterates all `JiraSync`s, skips projects that are not `jira?` or have no `jira_base_url`; `spec/jobs/jira_sync_job_spec.rb`.
- `config/schedule.yml` — `jira_sync` (`*/5 5-13`) and `jira_sync_off_hours` (hourly otherwise), Asia/Ho_Chi_Minh, queue `default`.
- `app/controllers/jira_syncs_controller.rb` — new/create/edit/update/destroy (permits `jira_project`, `parent_ticket`, `auto_sync`), redirects to the project.
- `app/controllers/jira_sync_runs_controller.rb` — `POST /projects/:project_id/jira_syncs/:id/run` ("Sync now"): one `ManualStartFlash#start_source_manually` call with `Jira::SyncCycleSource`; `spec/requests/jira_sync_runs_spec.rb`. CRUD coverage lives in `spec/requests/jira_syncs_spec.rb`; `spec/requests/projects_spec.rb` also touches the section.
- `app/views/jira_syncs/{new,edit,_form,_list}.html.erb` — form and the project-page list with last result and "Sync now".

## Importer rules

- Skip any key that already has a workflow in the project in any status (compare `TicketRef.key_for(workflow.jira_ticket)`) and a key repeated in one batch; ignore blank keys.
- New workflow = `Projects::WorkflowDefaults#attributes(kind: :development)` plus `jira_ticket` (`TicketRef.url_for(project.jira_base_url, key)`) and `branch_name`.
- A workflow that fails validation goes to `failed` as `"KEY: messages"`; the rest still import.

## Invariants

- Import is idempotent; re-running creates nothing new.
- `[]` means "ran, no tickets"; never create `tickets.json` on failure (missing/invalid file raises `FetchError`).
- No Jira tokens in the app; access is the agent's Atlassian MCP. Assignee/project/parent go into the prompt as data, never into shell text.
- Errors are recorded on `last_result` as `"failed: #{message}".truncate(250)`.

## Change checklist

- New field imported from a ticket: add it to the prompt example and `TicketRows` (keep it pure, default missing values), carry it through `TicketImporter#workflow_attributes`, add the Workflow column per `ai-worker-domain` if needed; update the fetch_prompt, ticket_rows and ticket_importer specs.
- Scope options (`jira_project`, `parent_ticket`): migration + `JiraSync`, `FetchPrompt` and `AgentFetcher#prompt`, controller `jira_sync_params`, `_form`, `_list` partial and `label`; update the specs for each.
- Cadence: change `FETCH_EVERY` on `Jira::SyncCycleSource` only or the `config/schedule.yml` crons; update `sync_cycle_source_spec.rb` and keep the doc in `ai-worker-detached-agent-runs` consistent.

## Verification

`RAILS_ENV=test bundle exec rspec spec/services/jira/{agent_fetcher,fetch_prompt,ticket_rows,ticket_ref,ticket_sync,ticket_importer,sync_cycle_source}_spec.rb spec/jobs/jira_sync_job_spec.rb spec/models/jira_sync_spec.rb spec/requests/jira_syncs_spec.rb spec/requests/jira_sync_runs_spec.rb`
