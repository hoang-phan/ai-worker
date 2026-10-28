---
name: ai-worker-workflow-screens
description: Owns workflow and stage screens, scoped controllers, helpers, templates, and image/time-log UI. Use for app/controllers/{workflows,workflow_*,stages}_controller.rb, app/helpers/{stages_helper,workflow_pages_helper}.rb, app/views/{workflows,stages}/**, or template_fill_controller.js.
---

# ai-worker-workflow-screens

Scope: workflow CRUD/detail pages and stage forms. `WorkflowTransitionsController` belongs to `ai-worker-workflow-lifecycle`; runbook lifecycle semantics belong to `ai-worker-runbooks`; dashboard badges in `WorkflowsHelper` belong to `ai-worker-project-dashboard`.

## File map

- `app/controllers/workflows_controller.rb` — project-nested workflow CRUD; only development and runbook workflows are created here.
- `app/controllers/workflow_runbooks_controller.rb` — run-stage, advance, and clone actions; follow `ai-worker-runbooks` for their semantics.
- `app/controllers/workflow_images_controller.rb` — deletes a workflow image.
- `app/controllers/workflow_time_logs_controller.rb` — project workflow batch time-log action; follow `ai-worker-jira-worklogs` for time-log behavior.
- `app/controllers/stages_controller.rb` — stage CRUD; runbook guards and params follow `ai-worker-runbooks`.
- `app/controllers/concerns/workflow_scoped.rb` — loads a workflow after `ProjectScoped`; `StagesController` supplies `params[:workflow_id]` through `workflow_id_param`.
- `app/helpers/stages_helper.rb` — stage form options and runbook/development stage-table helpers, including `stage_runnable?` and `current_stage_badge`.
- `app/helpers/workflow_pages_helper.rb` — `workflow_details_partial`, `workflow_advance_label`, and `runbook_copy_source_options` for workflow pages.
- `app/views/workflows/show.html.erb` — workflow detail page and stage-run history.
- `app/views/workflows/new.html.erb` — new-workflow wrapper.
- `app/views/workflows/edit.html.erb` — edit-workflow wrapper.
- `app/views/workflows/_form.html.erb` — shared workflow form shell.
- `app/views/workflows/_details.html.erb` — dispatches the workflow detail card.
- `app/views/workflows/_stages.html.erb` — workflow stage table.
- `app/views/workflows/_stage_runs.html.erb` — stage-run history.
- `app/views/workflows/form/_jira_fields.html.erb` — Jira workflow fields.
- `app/views/workflows/form/_task_fields.html.erb` — task workflow fields.
- `app/views/workflows/form/_runbook_fields.html.erb` — runbook fields; semantics belong to `ai-worker-runbooks`.
- `app/views/workflows/form/_images.html.erb` — workflow images fields.
- `app/views/workflows/details/_jira.html.erb` — Jira detail card.
- `app/views/workflows/details/_task.html.erb` — task detail card.
- `app/views/workflows/details/_runbook.html.erb` — runbook detail card.
- `app/views/workflows/details/_pr_review.html.erb` — PR-review detail card.
- `app/views/workflows/details/_log_time.html.erb` — time-log detail card; behavior belongs to `ai-worker-jira-worklogs`.
- `app/views/stages/new.html.erb` — new-stage wrapper.
- `app/views/stages/edit.html.erb` — edit-stage wrapper.
- `app/views/stages/_form.html.erb` — shared stage form shell.
- `app/views/stages/form/_runbook_fields.html.erb` — runbook-stage fields; semantics belong to `ai-worker-runbooks`.
- `app/views/stages/form/_command_field.html.erb` — stage command field.
- `app/views/stages/form/_prompt_fields.html.erb` — stage prompt fields.
- `app/javascript/controllers/template_fill_controller.js` — previews a selected prompt template in a stage form.
- `spec/requests/workflows_spec.rb` — workflow CRUD and detail-page requests.
- `spec/requests/workflow_runbooks_spec.rb` — workflow runbook action requests; semantics belong to `ai-worker-runbooks`.
- `spec/requests/workflow_images_spec.rb` — image deletion requests.
- `spec/requests/workflow_time_logs_spec.rb` — batch time-log requests.
- `spec/requests/stages_spec.rb` — stage form and CRUD requests; runbook behavior belongs to `ai-worker-runbooks`.
- `spec/helpers/stages_helper_spec.rb` — stage form and table helper coverage.
- `spec/helpers/workflow_pages_helper_spec.rb` — workflow-page helper coverage.

## Conventions

- Workflows and stages are always nested below a project. Include `ProjectScoped`, then `WorkflowScoped` for workflow-scoped controllers; do not redefine their loaders.
- Keep CRUD actions thin and re-render invalid forms with 422. State transitions stay in model/service owners: transitions in `ai-worker-workflow-lifecycle`, runbook guards and actions in `ai-worker-runbooks`, and time logging in `ai-worker-jira-worklogs`.
- Use the helper methods above to keep kind-specific rendering out of templates. Place new workflow form/detail sections in `workflows/form/` or `workflows/details/`, and stage sections in `stages/form/`.
- The workflow show page is the only StageRun observability screen; do not introduce a StageRuns controller.

## Verification

Run `RAILS_ENV=test bundle exec rspec spec/requests/{workflows,workflow_runbooks,workflow_images,workflow_time_logs,stages}_spec.rb spec/helpers/{stages_helper,workflow_pages_helper}_spec.rb`.
