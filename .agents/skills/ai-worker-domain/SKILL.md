---
name: ai-worker-domain
description: Applies ai-worker's data model discipline. Use for any task touching app/models/{project,workflow,stage,stage_run,prompt_template}.rb, app/models/stages/run_history.rb, app/models/workflows/{image_store,validator,label}.rb, app/models/projects/{slack_user_map,live_checkout,agent_lessons,skill_catalog,workflow_defaults,run_blockers}.rb, db/migrate/**, or db/schema.rb — including cross-cutting enum and migration rules.
---

# ai-worker-domain

Scope: `app/models/{project,workflow,stage,stage_run,prompt_template}.rb`, `app/models/stages/run_history.rb`, `app/models/workflows/{image_store,validator,label}.rb`, `app/models/projects/{slack_user_map,live_checkout,agent_lessons,skill_catalog,workflow_defaults,run_blockers}.rb`, `db/migrate/**`, and `db/schema.rb`, plus cross-cutting enum and migration rules. Do not read `app/jobs`, `app/services`, `app/controllers`, or `app/views` for this work — the model layer has no dependency on them, except where a model calls `Prompts::Renderer` / `AiCli::Output` (noted below). `db/schema.rb` is the source of truth for columns; this file does not repeat them. Proposal normalization/building and proposal imports have a cross-layer owner: `ai-worker-proposal-imports`.

End-to-end Slack-driven reviews of someone else's PR: `ai-worker-pr-review-workflows`.
Per-project settings across model, form, controller, prompts, tests, and onboarding docs: `ai-worker-project-settings`.

Browser-test behaviour behind the UAT/local readiness predicates, `Stage#local_test_unfinished?` and the `uat_*`/`local_test_*` run actions: `ai-worker-browser-tests`.

## File map (the whole scope)

- `app/models/project.rb` — associations are `has_many :workflows`, `:jira_syncs`, and `:bugsnag_syncs`, all `dependent: :destroy` (there is no `:agents` association). Persisted enums: `flow` is `standard` / `ci_loop` (with `flow_` prefix), and `kind` is `jira` / `personal`. Core validations require `name` and `local_directory`, reject the live app checkout, require a valid `repo_full_name` for Jira projects, and constrain Jira/Slack/URL fields and CI/brainstorm numeric limits. Exact readiness gates: `ci_loop_ready?` is `jira? && flow_ci_loop?`; `local_test_ready?` is `jira? && local_test_enabled? && local_url.present?`; `uat_test_ready?` is `uat_test_enabled? && uat_url.present?`. The \"Jira project with a site URL\" rule lives in one place: scope `Project.with_jira_site` and predicate `jira_site?` (used by `JiraSyncJob` and `Jira::HoursSync`). `add_agent_lessons(lessons)` persists merged review lessons via `Projects::AgentLessons` with `update_column` (no-op for an empty list; used by `Stages::PrCheckFinish#record_lessons`). Per-project settings columns, encrypted test passwords, and feature-conditional validations: `ai-worker-project-settings`.
- `app/models/workflow.rb` — `belongs_to :project`; `has_many :stages` ordered by `position, id` and `:time_logs`, both `dependent: :destroy`. Persisted `status` has 15 values: `pending`, `implementing`, `reviewing`, `done`, `errored`, `merged`, `jira_updated`, `waiting`, `uat_waiting`, `uat_testing`, `uat_tested`, `local_testing`, `ci_checking`, `ci_verifying`, `opening_pr`; `kind` is `development` / `pr_review` / `runbook`. `Workflows::Validator` owns kind/project-specific presence and variable validation; the model validates the optional GitHub PR URL format. `QUEUED_STATUSES` is only `pending`; `queued` is development workflows in that status.
- `app/models/workflows/{transitions,resume_status,ci_loop_resume,current_stage,stage_resolver,stage_seeder}.rb` — the status machine: manual start/resume/rollback, status → stage maps, `Workflow#current_stage`, initial stages. Owned by `ai-worker-workflow-lifecycle`.
- `app/models/workflows/runbook_navigator.rb` — owned by `ai-worker-runbooks`.
- `app/models/workflows/runbook_clone.rb` — owned by `ai-worker-runbooks`.
- `app/models/workflows/image_store.rb` — reference images as plain files under `tmp/workflow_images/<id>` (not Active Storage), exposed via `{IMAGES}`.
- `app/models/workflows/validator.rb` — `Workflows::Validator` (`validates_with` on Workflow): the kind/project-conditional presence rules, PR-review project check, variable-name check and `copy_stages_from_id` check. Spec: `spec/models/workflows/validator_spec.rb`. The `github_pr_url` format check stays in `workflow.rb`.
- `app/models/workflows/label.rb` — `label` / `brief` / `heading` display text.
- `app/models/workflows/variables.rb` — owned by `ai-worker-runbooks`.
- `app/models/workflows/stage_outputs.rb` — owned by `ai-worker-runbooks`.
- `app/models/projects/slack_user_map.rb` — parses `Project#slack_user_map` (`github-login=SlackUserID` lines) for reviewer tagging.
- `app/models/projects/live_checkout.rb` — `LiveCheckout.new(local_directory, app_root: Rails.root).live?`: real-path comparison behind `Project#runs_from_live_checkout?` (symlinks count; missing/blank dir is false).
- `app/models/projects/agent_lessons.rb` — `AgentLessons.new(text)`: `#lines` (stripped non-blank lines) and `#merge(new_lessons)` (case-insensitive de-dup, keeps newest `MAX` = 40, returns text); used by `Project#add_agent_lessons` for the `agent_lessons` column.
- `app/models/projects/skill_catalog.rb` — `SkillCatalog.new(local_directory)`: `#dir` (expanded `.agents/skills` path) and `#names` (sorted non-hidden subdirectories; `[]` for blank/missing dir), exposed as `Project#skill_catalog` and used by `shared/_skill_hints`.
- `app/models/projects/workflow_defaults.rb` — attributes a new workflow starts with (next position, default skills, PR skills, reviewer).
- `app/models/projects/workflow_reorder.rb` — owned by `ai-worker-project-dashboard`.
- `app/models/projects/workflow_list.rb` — owned by `ai-worker-project-dashboard`.
- `app/models/projects/run_blockers.rb` — the shared blocker messages used by the agent-run services' `#blockers` (`messages(*checks)`).
- `app/models/stage.rb` — `belongs_to :workflow`; optional `belongs_to :prompt_template`; ordered `has_many :stage_runs, dependent: :destroy`. Its persisted `STAGE_TYPES` mapping has 12 values: `implementation`, `pr_check`, `task`, `pr_review`, `jira_update`, `runbook_step`, `uat_test`, `local_test`, `ci_check`, `ci_verify`, `pr_create`, `simple_implementation`; `run_mode` is `agent` / `message` with `run_` prefix. There is no stage status column. Runbook validation requires `name`, requires `channel` for message stages, and format-validates optional `wait_for_workflow`. `effective_template` uses the assigned template or the lowest-id template of the same type.
- `app/models/stage_run.rb` — `belongs_to :stage`; `ACTIONS` is the closed, inclusion-validated 42-action audit-log set, and `history_for(workflow)` is newest-first (with `id` tie-breaker).
- `app/models/stages/run_history.rb` — pure queries over a stage's StageRun actions (newest first), no DB access.
- `app/models/prompt_template.rb` — a reusable prompt body for a `stage_type` (uses `Stage::STAGE_TYPES`, no separate mapping). Placeholders and built-in default bodies live in `app/services/prompts/**`, not on the model: see the `ai-worker-prompts` skill. `has_many :stages, dependent: :nullify`.
- `app/models/jira_sync.rb` — owned by `ai-worker-jira-ticket-sync`.
- `app/models/bugsnag_sync.rb` — owned by `ai-worker-bugsnag-triage`.
- `app/models/time_log.rb` — owned by `ai-worker-jira-worklogs`.
- `app/models/application_record.rb`, `concerns/` — Rails defaults.

## Conventions

- `Workflow`, `Project` and `Stage` keep thin one-line delegators; new behaviour goes into a focused PORO under the matching `app/models/<plural>/` folder (`workflows/`, `projects/`, `stages/`) with its own spec under `spec/models/<plural>/`. For behaviour-preserving extractions, splits, slimming, or moves, follow `ai-worker-refactoring`.
- `status` / `stage_type` / `kind` / `run_mode` / `action` are always closed, enumerable sets (Rails `enum` or the frozen `ACTIONS` array) — never a free-text column. Add new states to the existing enum/array rather than a parallel field. Enum integers are persisted: append, never renumber or reorder. `StageRun::ACTIONS` is likewise append-only. `Stage` and `PromptTemplate` share one `stage_type` mapping, the frozen `Stage::STAGE_TYPES` constant — edit it in one place only.
- Every migration needs an explicit `null: false, default:` for anything that drives control flow (status, kind, position, `processing`, enable flags). The scheduler polls these columns, so an unexpected `NULL` breaks it silently. Follow recent migrations such as `db/migrate/*_add_uat_testing.rb`. Data-moving migrations should only touch narrowly selected rows.
- `Workflow#skill_list` is the only place that parses the `skills` text column; if the format changes, update `Prompts::Renderer`'s `{SKILLS}` substitution too (owned by `ai-worker-prompts`).
- New placeholders: follow the checklist in `ai-worker-prompts`. New `StageRun::ACTIONS` values must be added before any code logs them (an unknown action fails validation).
- Describe model behaviour in specs, not by poking the real database. Write RSpec specs under `spec/models/` (or `spec/services/` for service objects) and run them with `RAILS_ENV=test bundle exec rspec`. Never run scratch scripts, `bin/rails runner` or console commands against the development database — it holds the user's real projects and workflows. Migrations on the development DB need a backup first and the user's say-so; for tests, `RAILS_ENV=test` loads `db/schema.rb`.
