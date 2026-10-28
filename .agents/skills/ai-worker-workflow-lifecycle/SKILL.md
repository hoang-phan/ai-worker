---
name: ai-worker-workflow-lifecycle
description: Owns Workflow status transitions, stage resolution, start, resume, and rollback. Use for app/models/workflows/{transitions,resume_status,ci_loop_resume,current_stage,stage_resolver,stage_seeder}.rb, app/models/workflow.rb, or WorkflowTransitionsController.
---

# ai-worker-workflow-lifecycle

Scope: how a `Workflow#status` maps to a stage, and the manual transitions (start, resume after an error, roll back to review). The pieces are small POROs behind one-line delegators on `Workflow`. Not repeated here: `RunbookNavigator` and runbook Run stage / Next in `ai-worker-runbooks`, ci_loop resume details in `ai-worker-ci-loop`, adding a status / stage type / `StageRun::ACTIONS` value in `ai-worker-stage-types`.

What `uat_testing` / `local_testing` runs do once resumed: `ai-worker-browser-tests`.

## File map

- `app/models/workflows/stage_resolver.rb` — `Workflows::StageResolver.stage_type_for(status:, kind:, personal:, ci_loop: false)` is a pure lookup. Map precedence: `kind == pr_review` -> `PR_REVIEW_STAGE_TYPE_BY_STATUS`, then `personal` -> `SIMPLE_STAGE_TYPE_BY_STATUS`, then `ci_loop` -> `CI_LOOP_STAGE_TYPE_BY_STATUS`, else `STAGE_TYPE_BY_STATUS` (`implementing` -> `implementation`, `reviewing` -> `pr_check`, `merged` -> `jira_update`, `uat_testing` -> `uat_test`, `local_testing` -> `local_test`, plus the ci_loop statuses). Unmapped statuses (`pending`, `done`, ...) give nil. `LAZY_STAGE_TYPES` (`jira_update uat_test local_test ci_check ci_verify pr_create simple_implementation`) are not seeded.
- `app/models/workflows/current_stage.rb` — `Workflow#current_stage`: a runbook's stage at `current_stage_id`, else the resolver's type with `ci_loop: development? && project.ci_loop_ready?`; nil when unmapped; lazy types via `find_or_create_by!`, others `find_by`.
- `app/models/workflows/stage_seeder.rb` — `Workflows::StageSeeder#call` seeds on create: runbook copies, `pr_review` -> `pr_review`, personal -> `task`, `ci_loop_ready?` -> the five ci_loop stages, else `implementation` + `pr_check`.
- `app/models/workflows/transitions.rb` — the manual transitions, each returning true when applied, false when the guard fails. Its `resume_status:` keyword seam defaults to a fresh `ResumeStatus` for the workflow:
  - `start!`: only `pending?`; a runbook calls `start_runbook!`, otherwise `implementing`.
  - `resume!`: only `errored?`; in one transaction sets `resume_status` and logs `'resumed'` on `current_stage` (nil-safe).
  - `rollback_to_review!`: needs `can_rollback_to_review?` (`done?`, `development?`, `github_pr_url` present); sets `reviewing` and logs `'rolled_back_to_review'`.
  - `can_run_stage?`, `request_stage_run!`, `can_advance?` are the runbook guards (`ai-worker-runbooks`).
- `app/models/workflows/resume_status.rb` — `Workflows::ResumeStatus#call`, first match wins. Its `ci_loop_resume:` keyword seam defaults to a `CiLoopResume` for the workflow while `call` reads workflow state live:
  1. `uat_test_at` present -> `:uat_testing`
  2. `Workflows::CiLoopResume#status` when non-nil (see `ai-worker-ci-loop`)
  3. `local_test_unfinished?` (the `local_test` stage's `Stage#local_test_unfinished?`) -> `:local_testing`
  4. development workflow with `github_pr_url` -> `:reviewing`
  5. else `:implementing`
- `app/models/workflows/ci_loop_resume.rb` — `Workflows::CiLoopResume#status`: nil unless development and `ci_loop_ready?`, else derived from the newest non-`resumed` StageRun.
- `app/models/workflow.rb` — `delegate :start!, :resume!, :resume_status, :can_rollback_to_review?, :rollback_to_review!, ... to: :transitions`; `current_stage` builds `CurrentStage`.
- `app/controllers/workflow_transitions_controller.rb` — `start`, `resume`, `rollback_to_review`: call the model method and redirect with a notice when true, an alert when false. No logic of its own.

## Invariants

- `Workflow#transitions` builds a new `Transitions` on every call. Never memoise it (or `current_stage`): they read live status, PR url and stages, and a cached object would act on stale state.
- A guard failure returns false and changes nothing; the controller only picks the flash message.
- `resumed` is the only action `CiLoopResume` skips and `RunHistory` resets rounds on; keep the name in step with `ai-worker-ci-loop`.
- A new status needs an entry in the maps above (and in `LAZY_STAGE_TYPES` if its stage is not seeded) and a decision in `ResumeStatus`; follow `ai-worker-stage-types`.

## Specs (`RAILS_ENV=test bundle exec rspec spec/models/workflows spec/requests/workflow_transitions_spec.rb`)

- `transitions_spec.rb` — start/resume/rollback guards, the logged `'resumed'` / `'rolled_back_to_review'` runs, runbook guards.
- `resume_status_spec.rb` — the precedence order (UAT over ci_loop over local test over PR).
- `ci_loop_resume_spec.rb` — newest-run -> status table, nil cases.
- `current_stage_spec.rb` — runbook, personal, pr_review, ci_loop, lazy creation once, nil for terminal statuses.
- `stage_resolver_spec.rb` — every status map and `LAZY_STAGE_TYPES`; `stage_seeder_spec.rb` — seeded stages per kind and runbook copy.
- `spec/requests/workflow_transitions_spec.rb` — POST start / resume / rollback_to_review redirects and flashes.
