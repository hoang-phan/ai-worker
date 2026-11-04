---
name: ai-worker-workflow-lifecycle
description: Owns Workflow status transitions, stage resolution, start, resume, and rollback. Use for app/models/workflows/{transitions,resume_status,stage_flow,current_stage,stage_resolver,stage_seeder,test_stage_adder}.rb, app/models/workflow.rb, or WorkflowTransitionsController.
---

# ai-worker-workflow-lifecycle

Scope: how a non-runbook workflow moves stage by stage (`current_stage_id`, with `Workflow#status` as the label of that stage), and the manual transitions (start, resume after an error, roll back to review). The pieces are small POROs behind one-line delegators on `Workflow`. Not repeated here: `RunbookNavigator` and runbook Run stage / Next in `ai-worker-runbooks`, ci_loop resume details in `ai-worker-ci-loop`, adding a status / stage type / `StageRun::ACTIONS` value in `ai-worker-stage-types`.

What `uat_testing` / `local_testing` runs do once resumed: `ai-worker-browser-tests`.

## File map

- `app/models/workflows/stage_flow.rb` — `Workflows::StageFlow`, the stage-by-stage engine (one per call, never memoised). `PIPELINE_ORDER` is the running order by stage type (`implementation simple_implementation task pr_review pr_create ci_check ci_verify local_test pr_check`), so a stage added later (`local_test`) still lands in place; `#pipeline` is the workflow's stages in that order (`local_test` only while `project.local_test_ready?`; post-merge `jira_update` / `uat_test` are not part of it). `STATUS_BY_STAGE_TYPE` is the status label of each stage. A stage ends one of three ways: **completed** -> `#complete!(stage)` enters `#stage_after` or sets `done` after the last; **failed** (an expected negative result: changes requested, checks failing) -> `#route_failed!(stage)` enters `#failure_target` (the stage selected in `stages.failure_stage_id`, else `DEFAULT_FAILURE_TYPE`: `pr_check` -> itself, `ci_verify` -> `ci_check`, `local_test` -> `pr_check`, else the stage itself), logs `failure_routed`, and once the stage was routed back `MAX_FAILURE_ROUNDS` times since its last `resumed` parks the workflow `errored` with `failure_rounds_exhausted` instead of looping; **error** (a broken run) stays in the stage and retries via `Stages::FailureHandler`, unchanged. `#enter!(stage, **attrs)` sets `current_stage_id`, the status, `Workflow::AI_RUN_RESET` and `attrs` in one update. `Workflow` delegates `stage_complete!`, `stage_route_failed!`, `stage_enter!` to it.
- `app/models/workflows/stage_resolver.rb` — `Workflows::StageResolver.stage_type_for(status:, kind:, personal:, ci_loop: false)` is the pure status -> stage lookup, now the fallback for workflows that predate `current_stage_id`, for statuses set by hand, and for the status-driven post-merge work (`merged` -> `jira_update`, `uat_testing` -> `uat_test`). Map precedence: `kind == pr_review` -> `PR_REVIEW_STAGE_TYPE_BY_STATUS`, then `personal` -> `SIMPLE_STAGE_TYPE_BY_STATUS`, then `ci_loop` -> `CI_LOOP_STAGE_TYPE_BY_STATUS`, else `STAGE_TYPE_BY_STATUS`. Unmapped statuses (`pending`, `done`, ...) give nil. `LAZY_STAGE_TYPES` (`jira_update uat_test local_test ci_check ci_verify pr_create simple_implementation`) are not seeded.
- `app/models/workflows/current_stage.rb` — `Workflow#current_stage`: a runbook's stage at `current_stage_id`; otherwise the stored pipeline stage while `status` is still the label of that stage (a status moved by hand, `done`, `errored` and the post-merge statuses fall through), else the resolver's type with `ci_loop: development? && project.ci_loop_ready?`; nil when unmapped; lazy types via `find_or_create_by!`, others `find_by`.
- `app/models/workflows/stage_seeder.rb` — `Workflows::StageSeeder#call` seeds on create: runbook copies, `pr_review` -> `pr_review`, personal -> `task`, `ci_loop_ready?` -> the five ci_loop stages, else `implementation` + `pr_check`. Standard and ci_loop workflows also get `local_test` / `uat_test` when the project saved that kind's credentials and ticked its `*_stage_auto_include`.
- `app/models/workflows/test_stage_adder.rb` — `Workflows::TestStageAdder`: adds the optional `local_test` / `uat_test` stage by hand. `addable_test_stages` / `add_test_stage!` (delegated from `Workflow`) need a development workflow, the project's credentials (`local_test_ready?` / `uat_test_ready?`), no existing stage and a status before the PR handoff (local) or the Jira update (UAT). A workflow only runs the testing when it has the stage (`Workflow#local_test_stage?` / `uat_test_stage?`).
- `app/models/workflows/transitions.rb` — the manual transitions, each returning true when applied, false when the guard fails. Its `resume_status:` and `flow:` keyword seams default to a fresh `ResumeStatus` and `StageFlow` for the workflow:
  - `start!`: only `pending?`; a runbook calls `start_runbook!`, otherwise `Workflows::StageFlow#enter!` on the first pipeline stage (`implementing` if there is none).
  - `resume!`: only `errored?`; in one transaction applies the `ResumeStatus::Target` (status and stage) and logs `'resumed'` on the target stage and on the stage that errored when different (nil-safe).
  - `rollback_to_review!`: needs `can_rollback_to_review?` (`done?`, `development?`, `github_pr_url` present); enters the `pr_check` stage and logs `'rolled_back_to_review'`.
  - `can_skip_stage?` / `skip_stage!`: an idle ci_loop check or verify stage is completed through `Workflows::StageFlow#complete!` and logs `'stage_skipped'`.
  - `can_run_stage?`, `request_stage_run!`, `can_advance?` are the runbook guards (`ai-worker-runbooks`).
- `app/models/workflows/resume_status.rb` — `Workflows::ResumeStatus#call` returns a `Target(status:, stage:, origin:)`, first match wins:
  1. `uat_test_at` present -> `:uat_testing` (no stage)
  2. a runbook -> `:implementing` (stage left alone)
  3. the stage that errored: the stored `current_stage_id` stage, else the stage of the newest non-`resumed` StageRun, else `pr_check` once a development workflow has a PR, else the first pipeline stage; its status is the resume status
  4. when that stage's last action is `ci_rounds_exhausted` the target is its failure target (the check) with a fresh budget
- `app/models/workflow.rb` — `delegate :start!, :resume!, :resume_status, :can_rollback_to_review?, :rollback_to_review!, ... to: :transitions`; `delegate :complete!, :route_failed!, :enter!, to: :stage_flow, prefix: :stage`; `current_stage` builds `CurrentStage`, `stage_flow` builds `StageFlow`.
- `app/controllers/workflow_transitions_controller.rb` — `start`, `resume`, `rollback_to_review`: call the model method and redirect with a notice when true, an alert when false. No logic of its own.
- `app/controllers/workflow_test_stages_controller.rb` — `create` (`POST test_stage`): `Workflow#add_test_stage!(params[:stage_type])`, notice or alert.

## Invariants

- `Workflow#transitions` builds a new `Transitions` on every call. Never memoise it (or `current_stage`): they read live status, PR url and stages, and a cached object would act on stale state.
- A guard failure returns false and changes nothing; the controller only picks the flash message.
- `resumed` is the only action `ResumeStatus` skips when finding the newest run and `RunHistory` resets rounds on (`completed_ci_rounds`, `routed_failure_rounds`); keep the name in step with `ai-worker-ci-loop`.
- A finish service never writes a pipeline status itself: it calls `stage_complete!` (success), `stage_route_failed!` (expected negative result) or `stage_enter!` (a specific stage), so `current_stage_id` and `status` cannot drift apart. Errors never route; they retry through `Stages::FailureHandler`.
- A stage added to the pipeline needs its type in `StageFlow::PIPELINE_ORDER` and `STATUS_BY_STAGE_TYPE`; a stage that can end failed also needs a `DEFAULT_FAILURE_TYPE` row and a `StageRun` action for it.
- A new status needs an entry in the maps above (and in `LAZY_STAGE_TYPES` if its stage is not seeded) and `StageFlow::STATUS_BY_STAGE_TYPE`; follow `ai-worker-stage-types`.

## Specs (`RAILS_ENV=test bundle exec rspec spec/models/workflows spec/requests/workflow_transitions_spec.rb`)

- `transitions_spec.rb` — start/rollback/skip guards, the logged `'rolled_back_to_review'` / `'stage_skipped'` runs, runbook guards.
- `stage_flow_spec.rb` — pipeline order, `complete!`, failure targets and defaults, `route_failed!` and its loop cap.
- `resume_status_spec.rb` — the resume target: UAT, stored stage, newest run, PR, exhausted CI loop.
- `transitions_resume_spec.rb` — `resume!` and `resume_status` (the resume half of the transitions).
- `current_stage_spec.rb` — runbook, personal, pr_review, ci_loop, stored stage vs status, lazy creation once, nil for terminal statuses.
- `stage_resolver_spec.rb` — every status map and `LAZY_STAGE_TYPES`; `stage_seeder_spec.rb` — seeded stages per kind and runbook copy.
- `test_stage_adder_spec.rb` and `spec/requests/workflow_test_stages_spec.rb` — manual add of the optional test stages.
- `spec/requests/workflow_transitions_spec.rb` — POST start / resume / rollback_to_review redirects and flashes.
