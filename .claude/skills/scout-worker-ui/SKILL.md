---
name: scout-worker-ui
description: Applies scout-worker's CRUD-screen discipline. Use for any task touching app/controllers/**, app/views/**, or config/routes.rb — the Projects/Workflows/PromptTemplates screens.
---

# scout-worker-ui

Scope: `app/controllers/**`, `app/views/**`, `config/routes.rb`. Read `app/models/*.rb` only for attribute/validation/enum names when building forms — do not modify models here (that's `scout-worker-domain`'s scope) and do not touch `app/jobs`/`app/services` (that's `scout-worker-orchestration`'s scope).

## File map (the whole scope)

- `config/routes.rb` — `resources :projects` nests `resources :workflows, except: :index` (a project's workflows are listed on the project's own `show` page, not a separate index); `resources :prompt_templates` is top-level; `root "projects#index"`.
- `app/controllers/projects_controller.rb` + `app/views/projects/{index,show,new,edit,_form}.html.erb` — Project CRUD. `show` also lists the project's workflows with their current stage and PR link.
- `app/controllers/workflows_controller.rb` + `app/views/workflows/{show,new,edit,_form}.html.erb` — Workflow CRUD, always nested under a project (`project_workflow_path(project, workflow)`). `show` also renders the workflow's stages and its full `StageRun` history (flattened across stages, newest first) — this is the only "observability" screen, there is no separate `StageRuns` controller.
- `app/controllers/prompt_templates_controller.rb` + `app/views/prompt_templates/{index,show,new,edit,_form}.html.erb` — Prompt Template CRUD. The form surfaces `PromptTemplate::PLACEHOLDERS` next to the body textarea as a cheatsheet.

## Conventions

- These are plain Rails CRUD controllers — no admin gem, no API-only mode. Keep that: `create`/`update` re-render `:new`/`:edit` with `status: :unprocessable_entity` on failure, `destroy` redirects with a flash `notice`, forms are plain `form_with model:` partials shared between `new`/`edit`.
- `Workflow#status`/`stage_type`/`PromptTemplate#stage_type` are Rails enums — render them with `f.select :status, Workflow.statuses.keys` (see `app/views/workflows/_form.html.erb`), never hardcode the string list in a view.
- `github_pr_url` is only ever set by `StageExecutor` (via `Github::Client`), never editable from these forms — don't add a form field for it.
- `PromptTemplate` enforces "one active template per stage_type" at the model layer (`before_save :deactivate_siblings`); the form just needs a checkbox and a short note explaining that saving as active deactivates the sibling, not any special controller logic.
