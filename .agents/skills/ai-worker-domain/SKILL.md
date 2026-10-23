---
name: ai-worker-domain
description: Applies ai-worker's data model discipline. Use for any task touching app/models/**, db/migrate/**, or db/schema.rb — adding/changing fields on Project, Workflow, Stage, StageRun, PromptTemplate, Agent, AgentDelegation, JiraSync or BugsnagSync, their enums, validations, or associations.
---

# ai-worker-domain

Scope: `app/models/**`, `db/migrate/**`, `db/schema.rb`. Do not read `app/jobs`, `app/services`, `app/controllers`, or `app/views` for this work — the model layer has no dependency on them, except where a model calls `Prompts::Renderer` / `AiCli::Output` (noted below). `db/schema.rb` is the source of truth for columns; this file does not repeat them.

## File map (the whole scope)

- `app/models/project.rb` — a local checkout plus, for `jira` projects, its GitHub repo. `enum :kind, { jira: 0, personal: 1 }` (jira = GitHub/PR flow driven by tickets; personal = local-only, one task description per workflow, no PR). `has_many :workflows, :agents, :jira_syncs, :bugsnag_syncs` (all `dependent: :destroy`). Holds per-project settings, grouped: defaults for new workflows (skills, reviewers), Jira (site URL, assignee, tester), Slack PR review and review pings (enable flag, mention, channels, GitHub→Slack user map), UAT testing (enable flag, URL, login, delay), local pre-review testing (same shape), shared test/CI instructions, and brainstorming (goal, limits, auto-start, last-run bookkeeping). UAT and local passwords are Active Record `encrypts` columns. Validations are conditional on kind or on the feature's enable flag. It also refuses a `local_directory` that is this app's own live checkout (agents branch, merge and migrate inside the clone).
- `app/models/workflow.rb` — one unit of automated work for a project: associations (`project`, `stages` ordered by `position, id`, `time_logs`), the enums, validations by kind/project kind, agent-run tracking columns (`finish_ai_run!` resets them), `QUEUED_STATUSES` / `queued`, `skill_list` / `pr_skill_list` / `reviewer_list`, `tracks_jira_after_merge?`, and thin one-line delegators to the objects below.
  - `enum :status` has 15 values (pending, implementing, reviewing, done, errored, merged, jira_updated, waiting, uat_waiting, uat_testing, uat_tested, local_testing, ci_checking, ci_verifying, opening_pr); the integers are persisted. `enum :kind` is `development` / `pr_review` / `runbook`.
- `app/models/workflows/transitions.rb` — manual lifecycle: start, resume after an error, roll back to review, runbook Run stage / Next guards.
- `app/models/workflows/runbook_navigator.rb` — runbook state machine: `start!`, `advance!`, next/previous stage. Runbook lifecycle and invariants: `ai-worker-runbooks`.
- `app/models/workflows/current_stage.rb` — `Workflow#current_stage` (runbook's `current_stage_id`, else via the resolver; lazy stage types created on first use).
- `app/models/workflows/stage_resolver.rb` — pure status/kind/project-kind → stage type mapping (all status→stage maps live here).
- `app/models/workflows/stage_seeder.rb` — initial stages on create, by kind and project kind; runbooks copy another runbook's stages.
- `app/models/workflows/runbook_clone.rb` — the runbook Clone button: same stages, only user-set variables.
- `app/models/workflows/ci_loop_resume.rb` — where an errored `ci_loop` workflow resumes, from its newest pre-review run.
- `app/models/workflows/image_store.rb` — reference images as plain files under `tmp/workflow_images/<id>` (not Active Storage), exposed via `{IMAGES}`.
- `app/models/workflows/label.rb` — `label` / `brief` / `heading` display text.
- `app/models/workflows/variables.rb` — runbook variables: `NAME=value` text form and user-typed vs stage-emitted (`input_variables` / `output_variable_names`).
- `app/models/workflows/stage_outputs.rb` — query object for successful runbook stage outputs (`all`, `latest_for(stage)`; only `stage_completed` runs count). `Variables` stays a pure parser.
- `app/models/projects/slack_user_map.rb` — parses `Project#slack_user_map` (`github-login=SlackUserID` lines) for reviewer tagging.
- `app/models/projects/live_checkout.rb` — `LiveCheckout.new(local_directory, app_root: Rails.root).live?`: real-path comparison behind `Project#runs_from_live_checkout?` (symlinks count; missing/blank dir is false).
- `app/models/projects/skill_catalog.rb` — `SkillCatalog.new(local_directory)`: `#dir` (expanded `.agents/skills` path) and `#names` (sorted non-hidden subdirectories; `[]` for blank/missing dir), exposed as `Project#skill_catalog` and used by `shared/_skill_hints`.
- `app/models/projects/workflow_defaults.rb` — attributes a new workflow starts with (next position, default skills, PR skills, reviewer).
- `app/models/projects/workflow_reorder.rb` — moves a workflow up/down the project's priority list.
- `app/models/projects/workflow_list.rb` — `WorkflowList.new(project, status:)`: the dashboard list (`status_filter` ignores invalid values, `workflows` filtered, `first_id`/`last_id` over the unfiltered list, `logged_seconds_for(workflow)` from `TimeLog.seconds_by_ticket`).
- `app/models/projects/run_blockers.rb` — the shared blocker messages used by the agent-run services' `#blockers` (`messages(*checks)`).
- `app/models/stage.rb` — one step of a workflow. `enum :stage_type` (built from the frozen `Stage::STAGE_TYPES` constant, 12 values: implementation, pr_check, task, pr_review, jira_update, runbook_step, uat_test, local_test, ci_check, ci_verify, pr_create, simple_implementation). There is **no stage status column**: progress is tracked on `Workflow#status` and in `StageRun` rows. `enum :run_mode, { agent, message }` (prefix `run_`) and the `name` / `channel` / `auto_advance` / `wait_for_workflow` columns are for runbook stages only. `prompt` is a per-stage text override that wins over any template, for any stage type. `belongs_to :agent, optional: true` (the project agent the stage runs as; `agent_belongs_to_workflow_project` rejects an agent from another project). `run_history` returns a `Stages::RunHistory`. `effective_template` is the explicitly assigned `prompt_template`, else the first `PromptTemplate` of the same `stage_type` (lowest id) — there is no "active" flag.
- `app/models/stage_run.rb` — one audit-log row per action taken on a stage (starts, completions, failures, merge/review/test outcomes, manual resume/rollback, runbook Next…); `StageRun.history_for(workflow)` is the newest-first history scope across a workflow's stages. `ACTIONS` is the closed set of valid `action` values, enforced by an inclusion validation — add new values there, not ad hoc strings elsewhere.
- `app/models/stages/run_history.rb` — pure queries over a stage's StageRun actions (newest first), no DB access.
- `app/models/prompt_template.rb` — a reusable prompt body for a `stage_type` (uses `Stage::STAGE_TYPES`, no separate mapping). Placeholders and built-in default bodies live in `app/services/prompts/**`, not on the model: see the `ai-worker-prompts` skill. `has_many :stages, dependent: :nullify`.
- Project agents (`app/models/{agent,agent_delegation,stage}.rb`): see `ai-worker-project-agents`.
- `app/models/jira_sync.rb` — one Jira query (project and/or parent ticket) for a project, with `auto_sync`, last-run bookkeeping and a `label`.
- `app/models/bugsnag_sync.rb` — one Bugsnag-project → Jira-project triage with thresholds and a `ledger` (JSON map of already-ticketed errors → Jira keys). Both have an `auto` scope.
- `app/models/time_log.rb` — mirror of the user's Jira worklogs; backs every logged-hours figure (see `ai-worker-jira-worklogs`).
- `app/models/application_record.rb`, `concerns/` — Rails defaults.

## Conventions

- `Workflow`, `Project` and `Stage` keep thin one-line delegators; new behaviour goes into a focused PORO under the matching `app/models/<plural>/` folder (`workflows/`, `projects/`, `stages/`) with its own spec under `spec/models/<plural>/`. For behaviour-preserving extractions, splits, slimming, or moves, follow `ai-worker-refactoring`.
- `status` / `stage_type` / `kind` / `run_mode` / `action` are always closed, enumerable sets (Rails `enum` or the frozen `ACTIONS` array) — never a free-text column. Add new states to the existing enum/array rather than a parallel field. Enum integers are persisted: append, never renumber or reorder. `Stage` and `PromptTemplate` share one `stage_type` mapping, the frozen `Stage::STAGE_TYPES` constant — edit it in one place only.
- Every migration needs an explicit `null: false, default:` for anything that drives control flow (status, kind, position, `processing`, enable flags). The scheduler polls these columns, so an unexpected `NULL` breaks it silently. Follow recent migrations such as `db/migrate/*_add_uat_testing.rb`. Data-moving migrations should only touch narrowly selected rows.
- `Workflow#skill_list` is the only place that parses the `skills` text column; if the format changes, update `Prompts::Renderer`'s `{SKILLS}` substitution too (owned by `ai-worker-orchestration`).
- New placeholders: follow the checklist in `ai-worker-prompts`. New `StageRun::ACTIONS` values must be added before any code logs them (an unknown action fails validation).
- Describe model behaviour in specs, not by poking the real database. Write RSpec specs under `spec/models/` (or `spec/services/` for service objects) and run them with `RAILS_ENV=test bundle exec rspec`. Never run scratch scripts, `bin/rails runner` or console commands against the development database — it holds the user's real projects and workflows. Migrations on the development DB need a backup first and the user's say-so; for tests, `RAILS_ENV=test` loads `db/schema.rb`.
