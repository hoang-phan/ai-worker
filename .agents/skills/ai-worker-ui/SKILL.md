---
name: ai-worker-ui
description: Applies ai-worker's CRUD-screen discipline for project CRUD/forms, prompt templates, settings, Jira/Bugsnag sync CRUD and runs, shared UI, remaining Stimulus controllers, and routes.
---

# ai-worker-ui

Scope: project CRUD/forms, prompt templates, settings, sync CRUD/run screens, shared UI, remaining Stimulus controllers, and `config/routes.rb`. Workflow and stage screens belong to `ai-worker-workflow-screens`; project dashboard/list screens belong to `ai-worker-project-dashboard`.

## File map

- `config/routes.rb` — project, sync, workflow, stage, prompt-template, settings, root, Sidekiq, and health routes. Keep existing helper names when routing a controller action.
- `app/controllers/projects_controller.rb` — project CRUD; dashboard `index`/`show` details belong to `ai-worker-project-dashboard`.
- `app/views/projects/_form.html.erb` — shared project form shell.
- `app/views/projects/new.html.erb` — new-project wrapper.
- `app/views/projects/edit.html.erb` — edit-project wrapper.
- `app/views/projects/form/_jira.html.erb` — Jira project fields.
- `app/views/projects/form/_uat_test.html.erb` — UAT fields.
- `app/views/projects/form/_ci_loop.html.erb` — CI-loop fields.
- `app/views/projects/form/_local_test.html.erb` — local-test fields.
- `app/views/projects/form/_brainstorm.html.erb` — brainstorming fields.
- `app/views/projects/form/_slack.html.erb` — Slack fields.
- `app/views/projects/form/_errors.html.erb` — project-form errors.
- `app/controllers/prompt_templates_controller.rb` — prompt-template CRUD.
- `app/views/prompt_templates/_form.html.erb` — prompt-template form and built-in tokens.
- `app/views/prompt_templates/index.html.erb` — prompt-template list.
- `app/views/prompt_templates/show.html.erb` — prompt-template detail.
- `app/views/prompt_templates/new.html.erb` — new prompt-template wrapper.
- `app/views/prompt_templates/edit.html.erb` — edit prompt-template wrapper.
- `app/controllers/settings_controller.rb` — agent-setting update.
- `app/controllers/settings/rotations_controller.rb` — rotation-weight update.
- `app/views/settings/show.html.erb` — both settings forms.
- `app/controllers/jira_syncs_controller.rb` — project Jira-sync CRUD.
- `app/controllers/jira_sync_runs_controller.rb` — Jira-sync run action and blocked-start feedback.
- `app/views/jira_syncs/_form.html.erb` — Jira-sync form.
- `app/views/jira_syncs/new.html.erb` — new Jira-sync wrapper.
- `app/views/jira_syncs/edit.html.erb` — edit Jira-sync wrapper.
- `app/controllers/bugsnag_syncs_controller.rb` — project Bugsnag-sync CRUD.
- `app/controllers/bugsnag_sync_runs_controller.rb` — Bugsnag-sync run action and blocked-start feedback.
- `app/views/bugsnag_syncs/_form.html.erb` — Bugsnag-sync form.
- `app/views/bugsnag_syncs/new.html.erb` — new Bugsnag-sync wrapper.
- `app/views/bugsnag_syncs/edit.html.erb` — edit Bugsnag-sync wrapper.
- `app/controllers/project_slack_syncs_controller.rb` — project Slack-sync “run now” action.
- `app/controllers/project_brainstorms_controller.rb` — project brainstorm “run now” action.
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

## CRUD conventions

- These are plain Rails server-rendered CRUD controllers. `create`/`update` re-render `:new`/`:edit` with `status: :unprocessable_entity` on failure; `destroy` redirects with a flash `notice`; forms are `form_with model:` partials shared between `new`/`edit`.
- Project-nested CRUD controllers include `ProjectScoped` followed by `ProjectChildCrud`; configure their association and flash label and keep only strong params locally. `ProjectSlackSyncsController` and `ProjectBrainstormsController` use `ProjectMemberScoped`; `ProjectsController` uses neither.
- Controllers stay thin. Do not put scheduler, agent, or git logic in a request; new “run now” actions include `ManualStartFlash` and make one `start_manually(...)` call.
- Enum-backed selects use the model’s own keys; system-set fields do not go in forms or strong params. Secrets are never rendered back into a form; blank means “keep”.
- Test with RSpec under `spec/`; never use development data, scratch runners, or destructive dev-server actions for verification.
