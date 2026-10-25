---
name: ai-worker-project-settings
description: Add or change a per-project setting across app/models/project.rb settings columns/validations, ProjectsController#project_params/create/update, app/views/projects/{_form,new,edit}.html.erb and app/views/projects/form/*, app/services/prompts/project_placeholders.rb tokens, spec/models/project_spec.rb, spec/requests/projects_spec.rb, and docs/ADDING_A_PROJECT.md.
---

# ai-worker-project-settings

Use for the usual cross-layer change to a setting stored on `Project`. It joins the existing domain, UI, prompt, and test conventions without replacing their owning skills.

## File map

- `app/models/project.rb` — project enums, encrypted UAT/local passwords, per-feature conditional validations, and readiness predicates; spec: `spec/models/project_spec.rb`.
- `app/controllers/projects_controller.rb` — CRUD (`create`/`update` render with 422 on failure) and `project_params`, including blank-password preservation; spec: `spec/requests/projects_spec.rb`.
- `app/views/projects/{_form,new,edit}.html.erb` — shared form shell, error rendering, and the new/edit wrappers; spec: `spec/requests/projects_spec.rb`.
- `app/views/projects/form/{_general,_instructions,_jira}.html.erb` — general fields, shared instructions, and Jira settings; spec: `spec/requests/projects_spec.rb`.
- `app/services/prompts/project_placeholders.rb` — project-derived `{TOKEN}` constants and values; spec: `spec/services/prompts/project_placeholders_spec.rb`.
- `spec/models/project_spec.rb` — project behavior and validation coverage.
- `spec/requests/projects_spec.rb` — project form rendering and create/update request behavior.
- `docs/ADDING_A_PROJECT.md` — operator requirements, safe self-registration, and project-skill onboarding.

## Checklist

1. Start with `ai-worker-domain`: add a migration and schema change. Every flag or other control-flow column has explicit `null: false, default:`. Do not run migrations against development data; use `RAILS_ENV=test` only for verification.
2. In `Project`, add the validation conditional on the applicable kind, flow, or enable predicate, matching the existing style (`if: :uat_test_enabled?`, `if: :flow_ci_loop?`, and so on). If consumers need a configuration gate, add one readiness predicate in the `uat_test_ready?` / `local_test_ready?` style rather than scattering checks.
3. Add the attribute to its section constant in `ProjectsController#project_params`; preserve the ordinary `create`/`update` behavior. For secrets, add the attribute to `KEEP_IF_BLANK`, declare `encrypts` in the model, never render the value back, and delete a blank submitted value so blank means “keep the saved one.”
4. Put the control in the relevant `app/views/projects/form/_<feature>.html.erb` fieldset, not inline in `projects/_form.html.erb`. Give user-visible behavior a `field-hint`; create a focused feature partial if no existing section fits.
5. If prompts consume the setting, follow `ai-worker-prompts`' placeholder checklist: add the `{TOKEN}` to `Prompts::ProjectPlaceholders`, document it, and add its prompt specs. Never make a secret a placeholder.
6. Add model validation coverage in `spec/models/project_spec.rb` and request coverage in `spec/requests/projects_spec.rb` for both create and update (including the blank-means-keep behavior for a secret).
7. Update `docs/ADDING_A_PROJECT.md` so an operator knows when and how to configure the setting.

## Owners and safety

- Detailed migration, schema, validation, encryption, and predicate rules: `ai-worker-domain`.
- Detailed controller/form and secret-rendering rules: `ai-worker-ui`.
- Placeholder, prompt documentation, and prompt-spec rules: `ai-worker-prompts`.
- Test setup and data-safety rules: `ai-worker-testing`.

Use `RAILS_ENV=test` only; never use development data for migration or verification work.
