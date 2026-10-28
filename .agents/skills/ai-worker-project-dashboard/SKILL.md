---
name: ai-worker-project-dashboard
description: Applies ai-worker's project-dashboard discipline. Use for app/controllers/projects_controller.rb (index/show), app/controllers/workflow_positions_controller.rb, app/controllers/workflow_bulk_deletes_controller.rb, app/models/projects/{workflow_list,workflow_reorder}.rb, app/views/projects/{index,show,_workflows,_workflow_row}.html.erb, app/helpers/{workflows,projects}_helper.rb, app/javascript/controllers/{bulk_delete,range_select}_controller.js, and their listed specs.
---

# ai-worker project dashboard

Scope: project index/show, workflow list/reordering, bulk delete, and status/kind badges; read affected code, as this map is not a substitute for it. Project CRUD/forms belong to `ai-worker-project-settings`.

## File map

- `app/controllers/projects_controller.rb` — `index` orders projects by name; `show` builds the one `@workflow_list` with `params[:status]`.
- `app/controllers/workflow_positions_controller.rb` — project-scoped `move` accepts only up/down, calls `Projects::WorkflowReorder#move`, and preserves the status filter in its redirect.
- `app/controllers/workflow_bulk_deletes_controller.rb` — project-scoped `destroy` deletes the selected in-project workflows and preserves the status filter in its redirect.
- `app/models/projects/workflow_list.rb` — validates the optional status, orders workflows by position/id, supplies the unfiltered first/last ids for arrows, and batches logged Jira seconds.
- `app/models/projects/workflow_reorder.rb` — swaps an in-project workflow with its neighbour and renumbers the complete priority list 1..n.
- `app/views/projects/index.html.erb` — name-ordered project table, new/edit/delete links, and the empty state.
- `app/views/projects/show.html.erb` — header/new-workflow actions and local-based rendering of the workflow, sync (Jira then Bugsnag in one `jira?` block), brainstorm, and Slack-review sections; the sync lists render from their owning feature directories.
- `app/views/projects/_workflows.html.erb` — short composer for the workflow status filter, Jira time-log bar, and workflow table partials.
- `app/views/projects/workflows/_status_filter.html.erb` — GET status filter form.
- `app/views/projects/workflows/_time_log_bar.html.erb` — Jira-only batch time-log form and preset-hour buttons.
- `app/views/projects/workflows/_table.html.erb` — bulk-delete bar and its scoped range-select workflow table, rows, and empty state.
- `app/views/projects/_workflow_row.html.erb` — position arrows, checkbox, labels/kind/status/time badges, PR/edit actions, and pending Start action.
- `app/helpers/projects_helper.rb` — `project_header_meta` (escaped directory + repo name), `workflow_status_filter_options`, `workflow_list_empty_message`, static-path `icon_svg`, and the `show_brainstorm_section?` / `show_slack_reviews_section?` visibility rules used by `show`.
- `app/helpers/workflows_helper.rb` — `WORKFLOW_STATUS_BADGE_CLASSES`, `workflow_status_badge_class`, `workflow_status_badge`, and `workflow_kind_badges` used by dashboard rows.
- `app/javascript/controllers/bulk_delete_controller.js` — selected-count label, enables Delete selected, and sets its confirm text from the ticked workflow checkboxes.
- `app/javascript/controllers/range_select_controller.js` — Shift-click range tick/untick and select-all for the dashboard deletion checkboxes; dispatches `range-select:changed` for the bulk-delete bar.

## Boundaries

- Time-log checkboxes, the batch form, and `TimeLogsHelper` are governed by `ai-worker-jira-worklogs`.
- The Jira and Bugsnag sync tables (`app/views/jira_syncs/_list.html.erb` and `app/views/bugsnag_syncs/_list.html.erb`) belong to `ai-worker-jira-ticket-sync` and `ai-worker-bugsnag-triage`, respectively.
- The `_brainstorm` section belongs to `ai-worker-brainstorm`.
- Workflow CRUD and detail pages belong to `ai-worker-workflow-screens`; lifecycle actions belong to `ai-worker-workflow-lifecycle` and runbook actions to `ai-worker-runbooks`.

## List and reorder conventions

- Preserve the current status filter through move and Start redirects so the user returns to the same filtered dashboard.
- `WorkflowList` accepts only `Workflow.statuses.keys`; blank or invalid statuses mean no filter.
- `first_id` and `last_id` always come from the unfiltered ordered list, even while displayed rows are filtered.
- Keep the canonical order as `position, id`; reordering an in-project item swaps neighbours and renumbers the whole list.
- A foreign workflow or an end-of-list move is a harmless no-op; unknown directions redirect with an alert.
- Do not query inside row loops: pass `Projects::WorkflowList#logged_seconds_for` as a local, with the list owning the grouped lookup.

## View and helper conventions

- Partials receive explicit locals, never dashboard instance variables; `show` owns the one `@workflow_list`.
- Retain the Jira/personal conditional columns and the select-all data contract when changing dashboard rows.
- Add every new workflow status to `WORKFLOW_STATUS_BADGE_CLASSES` and its helper expectation; unknown values fall back to neutral.
- Use `workflow_kind_badges` for review/runbook labels instead of duplicating badge markup in the row.

## Specs

- `spec/requests/project_dashboard_spec.rb` — index/show rendering, status filtering, dashboard sections, compact row controls, and time-log selection.
- `spec/requests/workflow_positions_spec.rb` — valid moves, duplicate positions, end no-ops, invalid direction, and status-preserving redirects.
- `spec/requests/workflow_bulk_deletes_spec.rb` — selected deletes, empty selection alert, cross-project ignore, and status-preserving redirects.
- `spec/models/projects/workflow_list_spec.rb` — valid/invalid filtering, unfiltered ends, empty lists, and grouped logged seconds.
- `spec/models/projects/workflow_reorder_spec.rb` — up/down movement, renumbering, ends, and foreign workflows.
- `spec/helpers/projects_helper_spec.rb` — header meta escaping, workflow filter/empty-state/icon rendering helpers, and both section-visibility predicates.
- `spec/helpers/workflows_helper_spec.rb` — every status badge mapping/fallback and workflow kind badges.
## Verification

Run `RAILS_ENV=test bundle exec rspec spec/requests/{project_dashboard,workflow_positions,workflow_bulk_deletes}_spec.rb spec/models/projects/{workflow_list,workflow_reorder}_spec.rb spec/helpers/{workflows,projects}_helper_spec.rb` for dashboard changes.
