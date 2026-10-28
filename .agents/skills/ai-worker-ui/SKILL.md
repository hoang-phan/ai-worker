---
name: ai-worker-ui
description: Applies ai-worker's generic Rails CRUD-screen discipline for ProjectsController CRUD, shared UI, stylesheets, remaining Stimulus controllers, and routes. Use for those screens when no narrower skill owns them.
---

# ai-worker-ui

Scope: ProjectsController CRUD, shared UI, stylesheets under `app/assets/stylesheets/`, remaining Stimulus controllers, and `config/routes.rb`. Workflow and stage screens belong to `ai-worker-workflow-screens`; project dashboard/list screens belong to `ai-worker-project-dashboard`.

## File map

- `config/routes.rb` — project, sync, workflow, stage, prompt-template, settings, root, Sidekiq, and health routes. Keep existing helper names when routing a controller action.
- `app/controllers/concerns/project_scoped.rb` — project loading for nested controllers.
- `app/controllers/concerns/project_child_crud.rb` — reusable project-nested CRUD actions.
- `app/controllers/concerns/project_member_scoped.rb` — project loading for `/projects/:id` member actions.
- `app/controllers/concerns/manual_start_flash.rb` — `start_source_manually` runs `AgentRuns::ManualStart.for(source)` and maps the result to redirect + flash.
- `app/helpers/action_links_helper.rb` — reusable destructive links and inline button forms; spec: `spec/helpers/action_links_helper_spec.rb`.
- `app/views/layouts/application.html.erb` — navigation and flashes; spec: `spec/requests/layout_spec.rb`.
- `app/views/layouts/mailer.html.erb` — mailer HTML layout.
- `app/views/layouts/mailer.text.erb` — mailer text layout.
- `app/assets/stylesheets/01_base.css` — design tokens (`:root`) and global resets; new tokens go here.
- `app/assets/stylesheets/02_navigation.css` — top navigation / site header.
- `app/assets/stylesheets/03_page_layout.css` — page shell and page header.
- `app/assets/stylesheets/04_flash.css` — flash notice/alert banners.
- `app/assets/stylesheets/05_cards.css` — card surfaces.
- `app/assets/stylesheets/06_tables.css` — tables, empty states, icon buttons.
- `app/assets/stylesheets/07_badges.css` — status badges.
- `app/assets/stylesheets/08_buttons.css` — buttons and action links.
- `app/assets/stylesheets/09_forms.css` — form fields, submits, error summary.
- `app/assets/stylesheets/10_misc.css` — code blocks, chips, muted text, batch bar.
- Stylesheet convention: Propshaft `:app` loads CSS alphabetically — keep the numeric prefixes so cascade order stays base → navigation → … → misc. Put new rules in the matching area file; design tokens live in `01_base.css`. Do not add `@import` (would double-load with `:app`). Spec: `spec/requests/layout_spec.rb`.
- `app/views/shared/_skill_hints.html.erb` — clickable project skill hints.
- `app/views/shared/_error_summary.html.erb` — form validation errors.
- `app/views/shared/_skills_field.html.erb` — reusable skill textarea and chips.
- `app/views/pwa/manifest.json.erb` — PWA manifest.
- `app/views/pwa/service-worker.js` — PWA service worker.
- `app/javascript/controllers/skill_insert_controller.js` — inserts a selected skill into its textarea.
- `app/javascript/controllers/select_all_controller.js` — project-table checkbox selection.

## Owned elsewhere

- Settings screen (`app/controllers/settings_controller.rb`, `app/controllers/settings/rotations_controller.rb`, `app/controllers/concerns/settings_screen.rb`, `app/views/settings/show.html.erb`, and their request specs) — `ai-worker-cli-selection`.
- `app/controllers/projects_controller.rb` — CRUD → `ai-worker-project-settings`, index/show → `ai-worker-project-dashboard`.
- Project form partials (`app/views/projects/{_form,new,edit}.html.erb`, `app/views/projects/form/*`) — `ai-worker-project-settings`.
- Prompt-template CRUD (`app/controllers/prompt_templates_controller.rb`, `app/views/prompt_templates/**`, `spec/requests/prompt_templates_spec.rb`) — `ai-worker-prompts`.
- Jira sync CRUD, run actions, and views (`app/controllers/jira_syncs_controller.rb`, `app/controllers/jira_sync_runs_controller.rb`, `app/views/jira_syncs/**`) — `ai-worker-jira-ticket-sync`.
- Bugsnag sync CRUD, run actions, and views (`app/controllers/bugsnag_syncs_controller.rb`, `app/controllers/bugsnag_sync_runs_controller.rb`, `app/views/bugsnag_syncs/**`) — `ai-worker-bugsnag-triage`.
- Project brainstorm action (`app/controllers/project_brainstorms_controller.rb`) — `ai-worker-brainstorm`.
- Project Slack-sync action (`app/controllers/project_slack_syncs_controller.rb`) — `ai-worker-pr-review-workflows`.

## CRUD conventions

- These are plain Rails server-rendered CRUD controllers. `create`/`update` re-render `:new`/`:edit` with `status: :unprocessable_entity` on failure; `destroy` redirects with a flash `notice`; forms are `form_with model:` partials shared between `new`/`edit`.
- Project-nested CRUD controllers include `ProjectScoped` followed by `ProjectChildCrud`; configure their association and flash label and keep only strong params locally. `ProjectSlackSyncsController` and `ProjectBrainstormsController` use `ProjectMemberScoped`; `ProjectsController` uses neither.
- Controllers stay thin. Do not put scheduler, agent, or git logic in a request; new “run now” actions include `ManualStartFlash` and make one `start_source_manually(...)` call.
- Render destructive links with `delete_link_to` and single-action inline forms with `inline_button_to`.
- Enum-backed selects use the model’s own keys; system-set fields do not go in forms or strong params. Secrets are never rendered back into a form; blank means “keep”.
- Test with RSpec under `spec/`; never use development data, scratch runners, or destructive dev-server actions for verification.
