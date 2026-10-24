---
name: ai-worker-ui
description: Applies ai-worker's generic Rails CRUD-screen discipline for ProjectsController CRUD, prompt templates, settings and rotations, shared UI, remaining Stimulus controllers, and routes.
---

# ai-worker-ui

Scope: ProjectsController CRUD, prompt templates, settings and rotations, shared UI, remaining Stimulus controllers, and `config/routes.rb`. Workflow and stage screens belong to `ai-worker-workflow-screens`; project dashboard/list screens belong to `ai-worker-project-dashboard`.

## File map

- `config/routes.rb` — project, sync, workflow, stage, prompt-template, settings, root, Sidekiq, and health routes. Keep existing helper names when routing a controller action.
- `app/controllers/projects_controller.rb` — project CRUD; dashboard `index`/`show` details belong to `ai-worker-project-dashboard`.
- `app/controllers/prompt_templates_controller.rb` — prompt-template CRUD.
- `app/views/prompt_templates/_form.html.erb` — prompt-template form and built-in tokens.
- `app/views/prompt_templates/index.html.erb` — prompt-template list.
- `app/views/prompt_templates/show.html.erb` — prompt-template detail.
- `app/views/prompt_templates/new.html.erb` — new prompt-template wrapper.
- `app/views/prompt_templates/edit.html.erb` — edit prompt-template wrapper.
- `app/controllers/settings_controller.rb` — agent-setting update.
- `app/controllers/settings/rotations_controller.rb` — rotation-weight update.
- `app/views/settings/show.html.erb` — both settings forms.
- `app/controllers/concerns/project_scoped.rb` — project loading for nested controllers.
- `app/controllers/concerns/project_child_crud.rb` — reusable project-nested CRUD actions.
- `app/controllers/concerns/project_member_scoped.rb` — project loading for `/projects/:id` member actions.
- `app/controllers/concerns/manual_start_flash.rb` — `AgentRuns::ManualStart` redirect and flash mapping.
- `app/controllers/concerns/settings_screen.rb` — settings loading and 422 rendering.
- `app/views/layouts/application.html.erb` — navigation and flashes.
- `app/views/layouts/mailer.html.erb` — mailer HTML layout.
- `app/views/layouts/mailer.text.erb` — mailer text layout.
- `app/views/shared/_skill_hints.html.erb` — clickable project skill hints.
- `app/views/shared/_error_summary.html.erb` — form validation errors.
- `app/views/shared/_skills_field.html.erb` — reusable skill textarea and chips.
- `app/views/pwa/manifest.json.erb` — PWA manifest.
- `app/views/pwa/service-worker.js` — PWA service worker.
- `app/javascript/controllers/skill_insert_controller.js` — inserts a selected skill into its textarea.
- `app/javascript/controllers/select_all_controller.js` — project-table checkbox selection.

## Owned elsewhere

- Project form partials (`app/views/projects/{_form,new,edit}.html.erb`, `app/views/projects/form/*`) — `ai-worker-project-settings`.
- Jira sync CRUD, run actions, and views (`app/controllers/jira_syncs_controller.rb`, `app/controllers/jira_sync_runs_controller.rb`, `app/views/jira_syncs/**`) — `ai-worker-jira-ticket-sync`.
- Bugsnag sync CRUD, run actions, and views (`app/controllers/bugsnag_syncs_controller.rb`, `app/controllers/bugsnag_sync_runs_controller.rb`, `app/views/bugsnag_syncs/**`) — `ai-worker-bugsnag-triage`.
- Project brainstorm action (`app/controllers/project_brainstorms_controller.rb`) — `ai-worker-brainstorm`.
- Project Slack-sync action (`app/controllers/project_slack_syncs_controller.rb`) — `ai-worker-pr-review-workflows`.

## CRUD conventions

- These are plain Rails server-rendered CRUD controllers. `create`/`update` re-render `:new`/`:edit` with `status: :unprocessable_entity` on failure; `destroy` redirects with a flash `notice`; forms are `form_with model:` partials shared between `new`/`edit`.
- Project-nested CRUD controllers include `ProjectScoped` followed by `ProjectChildCrud`; configure their association and flash label and keep only strong params locally. `ProjectSlackSyncsController` and `ProjectBrainstormsController` use `ProjectMemberScoped`; `ProjectsController` uses neither.
- Controllers stay thin. Do not put scheduler, agent, or git logic in a request; new “run now” actions include `ManualStartFlash` and make one `start_manually(...)` call.
- Enum-backed selects use the model’s own keys; system-set fields do not go in forms or strong params. Secrets are never rendered back into a form; blank means “keep”.
- Test with RSpec under `spec/`; never use development data, scratch runners, or destructive dev-server actions for verification.
