---
name: ai-worker-domain
description: Applies ai-worker's data model discipline. Use for any task touching app/models/**, db/migrate/**, or db/schema.rb — adding/changing fields on Project, Workflow, Stage, StageRun, or PromptTemplate, their enums, validations, or associations.
---

# ai-worker-domain

Scope: `app/models/**`, `db/migrate/**`, `db/schema.rb`. Do not read `app/jobs`, `app/services`, `app/controllers`, or `app/views` for this work — the model layer has no dependency on them.

## File map (the whole scope)

- `app/models/project.rb` — a local checkout + its GitHub repo. `has_many :workflows`.
- `app/models/workflow.rb` — one Jira ticket's automation run. `belongs_to :project`, `has_many :stages` (ordered by `position`). `enum :status, { active: 0, closed: 1 }`. `skill_list` splits the comma-separated `skills` text column. `after_create` seeds exactly two stages (`implementation` position 1, `pr_check` position 2). `next_stage` returns the first `pending` stage in position order.
- `app/models/stage.rb` — one step of a workflow. `enum :stage_type, { implementation: 0, pr_check: 1 }`, `enum :status, { pending: 0, in_progress: 1, completed: 2, failed: 3 }`. `effective_template` falls back to the active default `PromptTemplate` for its `stage_type` when no template is assigned directly.
- `app/models/stage_run.rb` — one audit-log row per execution attempt of a stage (a `pr_check` stage runs repeatedly, so it accumulates many rows). `ACTIONS` is the closed set of valid `action` values — add new values there, not ad hoc strings elsewhere.
- `app/models/prompt_template.rb` — a reusable prompt body containing `{JIRA}`, `{PR}`, `{REVIEWER}`, `{SKILLS}` placeholders (`PLACEHOLDERS` constant). `before_save` enforces "exactly one active template per stage_type" by deactivating siblings.

## Conventions

- `status`/`stage_type`/`action` are always closed, enumerable sets (Rails `enum` or a frozen `ACTIONS` array) — never a free-text status column. If you need a new state, add it to the existing enum/array rather than introducing a parallel field.
- Every new migration needs an explicit `null: false, default:` for anything that drives control flow (status, position, active) — this app polls these columns from a cron job, so an unexpected `NULL` breaks scheduling silently. Match the existing migrations under `db/migrate/2026...create_workflows.rb` / `..._create_stages.rb` for the pattern.
- `Workflow#skill_list` is the only place that parses the `skills` text column — if you change its format (e.g. to a real join table), update it there and update `Prompts::Renderer`'s `{SKILLS}` substitution (owned by `ai-worker-orchestration`, not this skill) to match.
- After adding/changing a migration: `bin/rails db:migrate`, then sanity-check in `bin/rails runner` the way the models were verified originally — create a `Project`/`Workflow`, confirm `next_stage` and `effective_template` behave, before touching anything UI- or job-related.
