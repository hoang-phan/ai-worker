---
name: ai-worker-project-settings
description: Add or change a per-project setting. Use for app/models/project.rb settings columns, app/models/projects/validator.rb validations, ProjectsController#project_params/create/update, app/views/projects/{_form,new,edit}.html.erb and app/views/projects/form/*, app/services/prompts/project_placeholders.rb tokens, spec/models/project_spec.rb, spec/models/projects/validator_spec.rb, spec/requests/projects_spec.rb, and docs/ADDING_A_PROJECT.md.
---

# ai-worker-project-settings

Use for the usual cross-layer change to a setting stored on `Project`. It joins the existing domain, UI, prompt, and test conventions without replacing their owning skills.

## File map

- `app/models/project.rb` — project enums, encrypted UAT/local passwords, readiness predicates, and `validates_with Projects::Validator`; validation rules live in `app/models/projects/validator.rb` (spec: `spec/models/projects/validator_spec.rb`); project behavior spec: `spec/models/project_spec.rb`.
- `app/controllers/projects_controller.rb` — owns `new`/`edit`/`create`/`update`/`destroy`; `project_params` is a thin forwarder to `Projects::SettingsParams` (`create`/`update` render with 422 on failure); `index`/`show` belong to `ai-worker-project-dashboard`; spec: `spec/requests/projects_spec.rb`.
- `app/services/projects/settings_params.rb` — authoritative section attribute allowlists, strong-parameter filtering, and blank UAT/local password removal; spec: `spec/services/projects/settings_params_spec.rb`.
- `app/views/projects/{_form,new,edit}.html.erb` — shared form shell, error rendering, and the new/edit wrappers; spec: `spec/requests/projects_spec.rb`.
- `app/views/projects/form/{_general,_instructions,_jira}.html.erb` — general fields, shared instructions, and Jira settings; spec: `spec/requests/projects_spec.rb`.
- `app/services/prompts/project_placeholders.rb` — project-derived `{TOKEN}` constants and values; spec: `spec/services/prompts/project_placeholders_spec.rb`.
- `spec/models/project_spec.rb` — project behavior and validation coverage.
- `spec/requests/projects_spec.rb` — project form rendering and create/update request behavior.
- `docs/ADDING_A_PROJECT.md` — operator requirements, safe self-registration, and project-skill onboarding.

## Checklist

1. Start with `ai-worker-domain`: add a migration and schema change. Every flag or other control-flow column has explicit `null: false, default:`. Do not run migrations against development data; use `RAILS_ENV=test` only for verification.
2. In `Projects::Validator`, add the validation conditional on the applicable kind, flow, or enable predicate, matching the existing style (`if project.uat_test_enabled?`, `if project.flow_ci_loop?`, and so on — pass the project into every helper). Keep `validates :name, presence: true` on `Project`. If consumers need a configuration gate, add one readiness predicate on `Project` in the `uat_test_ready?` / `local_test_ready?` style rather than scattering checks. Cover the new rule in `spec/models/projects/validator_spec.rb`.
3. Add the attribute to its section constant in `Projects::SettingsParams`; preserve the ordinary `create`/`update` behavior through `ProjectsController#project_params`. For secrets, add the attribute to `KEEP_IF_BLANK`, declare `encrypts` in the model, never render the value back, and delete a blank submitted value so blank means “keep the saved one.” Add focused `SettingsParams` coverage for the allowlist and password filtering.
4. Put the control in the relevant `app/views/projects/form/_<feature>.html.erb` fieldset, not inline in `projects/_form.html.erb`. Give user-visible behavior a `field-hint`; create a focused feature partial if no existing section fits.
5. If prompts consume the setting, follow `ai-worker-prompts`' placeholder checklist: add the `{TOKEN}` to `Prompts::ProjectPlaceholders`, document it, and add its prompt specs. Never make a secret a placeholder.
6. Add validation coverage in `spec/models/projects/validator_spec.rb` (and a thin delegation smoke test in `spec/models/project_spec.rb` only if needed) and request coverage in `spec/requests/projects_spec.rb` for both create and update (including the blank-means-keep behavior for a secret).
7. Update `docs/ADDING_A_PROJECT.md` so an operator knows when and how to configure the setting.

## Owners and safety

- Detailed migration, schema, validation, encryption, and predicate rules: `ai-worker-domain`.
- Detailed controller/form and secret-rendering rules: `ai-worker-ui`.
- Placeholder, prompt documentation, and prompt-spec rules: `ai-worker-prompts`.
- Test setup and data-safety rules: `ai-worker-testing`.

Use `RAILS_ENV=test` only; never use development data for migration or verification work.
