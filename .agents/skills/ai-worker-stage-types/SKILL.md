---
name: ai-worker-stage-types
description: Checklist for adding, renaming or changing an ai-worker stage type, a Workflow status, or an agent result marker line (e.g. LOCAL_TEST_RESULT). Use when a change spans Stage, StageRun::ACTIONS, Workflow, StageExecutor, prompts, AiCli::Output and the scheduler together — uat_test and local_test are the worked examples.
---

# ai-worker-stage-types

A stage type crosses models, services, jobs and views, and is easy to get half-right. Follow the checklist in order. Per-layer rules live elsewhere: `ai-worker-domain` (models, migrations), `ai-worker-orchestration` (jobs/services), `ai-worker-testing` (specs), `ai-worker-ui` (views). This file only lists the touch points. Worked example throughout: `local_test`.

## Lifecycle

`Workflow#status` -> `Workflow#current_stage` (via `Workflows::StageResolver::STAGE_TYPE_BY_STATUS`) -> `StageExecutor#call` dispatches on `stage.stage_type` to a `start_*` method -> `start_ai_run` spawns a detached agent (`processing: true`, pid/log in `ai_*` columns) -> later scheduler ticks hit `StageExecutor#poll_ai_run`, which delegates to `AiCli::RunPoller` -> when done, `finalize_success` hands the output to `Stages::CompletionHandler#call`, which dispatches on stage type to a `finish_*` method -> the handler writes `Workflow::AI_RUN_RESET.merge(status: <next>)`, logs a `StageRun` action, runs side effects. Failures go to `Stages::FailureHandler` (via `StageExecutor#fail_stage`).

local_test: `implementing` -> (`CompletionHandler#finish_implementation` sets `local_testing` when `project.local_test_ready?`) -> `StageExecutor#start_local_test` -> `CompletionHandler#finish_local_test` -> `reviewing`. A failed round feeds `local_test_feedback` to the next `pr_check` run, which may send the workflow back to `local_testing` (`Stages::LocalTestPolicy.retest_after_fix?` in `finish_pr_check`).

## Checklist (in order)

1. **Migration/enum values** (see `ai-worker-domain`). Enum integers are stored: append, never renumber.
   - `Stage` `enum :stage_type` in `app/models/stage.rb` **and the duplicate** `enum :stage_type` in `app/models/prompt_template.rb` (keep identical).
   - `Workflow` `enum :status` in `app/models/workflow.rb` (`local_testing: 11`).
2. **`StageRun::ACTIONS`** (`app/models/stage_run.rb`): add every action the new code will `log(...)`. Validation rejects unknown actions, so this comes before any handler code (`local_test_completed`, `local_test_failing`, `local_test_retest_scheduled`, `local_test_rounds_exhausted`).
3. **Stage helpers** (`app/models/stage.rb`): history queries the flow needs, e.g. `completed_local_test_rounds`, `local_test_unfinished?`. Use `last_action` (ordered by id), not the association's default `created_at desc` order.
4. **Workflow wiring** (`app/models/workflow.rb`):
   - `app/models/workflows/stage_resolver.rb`: `STAGE_TYPE_BY_STATUS` (jira projects; `workflow.rb` only aliases it). Also `SIMPLE_STAGE_TYPE_BY_STATUS` (personal) / `PR_REVIEW_STAGE_TYPE_BY_STATUS` only if those kinds reach the stage.
   - Same file, `LAZY_STAGE_TYPES` (`%w[jira_update uat_test local_test]`): a stage type not seeded at creation must be listed, otherwise `current_stage` returns nil and the scheduler silently skips the workflow.
   - Seeding is `app/models/workflows/stage_seeder.rb` (called from `Workflow`): only add the type there if every new workflow needs it up front (local_test is lazily created instead).
   - `Workflow#resume_status` (still in `workflow.rb`): where an `errored` workflow returns to (`:uat_testing`, `:local_testing` via private `local_test_unfinished?`). Without it a failure resumes into the wrong status.
5. **Prompt default** (`app/services/prompts/defaults.rb`): add the body to `Prompts::Defaults` (constant plus an entry in `BODIES`, keyed by stage_type string); no `Prompts::StagePrompt` change needed. Placeholders are rendered by `Prompts::Renderer`.
6. **Result marker** (`app/services/ai_cli/output.rb`): one method per marker line (`local_test_result`, `retest_requested?`, `local_test_feedback_block`), anchored regex, take the **last** match (the log echoes the prompt's own example). The prompt body must tell the agent to print the exact marker.
7. **Start path** (`app/services/stage_executor.rb`): add a `when "local_test" then start_local_test` arm in `#call`, and the `start_*` method. Validate config first (`AiCli::BrowserTestRun#validate!` raises `AiCli::CommandError`, handled by `fail_stage`), then `start_ai_run` (or `start_browser_test`).
8. **Finish handler** (`app/services/stages/completion_handler.rb`): add a `when` arm in `CompletionHandler#call` and a `finish_*` method (`finish_local_test`). Parse the marker; a missing marker raises `AiCli::CommandError` so the stage fails visibly (rescued by `StageExecutor#call`). Put pure decisions in their own object: PR-check outcome in `stages/pr_check_decision.rb`, local-test retry/outcome rules in `stages/local_test_policy.rb`, best-effort reviewer notify/auto-merge in `stages/review_handoff.rb`. Failure handling (consecutive-failure cap, `errored`) is `stages/failure_handler.rb`; run polling/stale-kill is `ai_cli/run_poller.rb`.
9. **Scheduler** (`app/jobs/workflow_scheduler_job.rb`, queries in `app/services/scheduling/workflow_queries.rb`): add the new in-flight status to `WorkflowQueries::ACTIVE_STATUSES` (or `POLLING_STATUSES` for statuses entered outside the main loop, or a phase like `run_uat_phase` for time-gated ones), and to `BUSY_STATUSES` if the post-merge phase must not run during it (`work_in_progress?`). See `ai-worker-scheduling`.
10. **Views/controllers**: add the status to the badge `case` in `app/views/workflows/show.html.erb` and `app/views/projects/show.html.erb` (`badge-info` / `badge-success`). Project-level toggles/fields go in `app/views/projects/_form.html.erb` and `ProjectsController#project_params`, plus `Project#local_test_ready?`-style readiness predicate. `PromptTemplate` forms list types from the enum automatically.

## Invariants

- Every logged action is in `StageRun::ACTIONS` first (step 2).
- Every finish handler's `workflow.update!` merges `Workflow::AI_RUN_RESET` (clears `processing`, pid, log path, offset). Forget it and the workflow polls a dead run forever. `Stages::FailureHandler` already does this; only the success paths are yours.
- A finish handler leaves the workflow in a status the scheduler picks up (or terminal). Check the status appears in step 9's lists (`Scheduling::WorkflowQueries`).
- Counting rounds/retries: cap them (`Stages::LocalTestPolicy::MAX_LOCAL_TEST_ROUNDS`) and log an `_exhausted` action rather than looping.
- New result markers get an `AiCli::Output` method **and** a spec; never regex agent output inline in `StageExecutor` or a handler.
- Handler-side effects that reach git/GitHub/Slack follow `ai-worker-orchestration` (argv arrays, rescue the typed `*::CommandError`).

## Specs to add (see `ai-worker-testing`)

- Model: `spec/models/stage_spec.rb` (helpers), `spec/models/workflow_spec.rb` (`current_stage` creating the stage via `LAZY_STAGE_TYPES`, `resume_status`/`resume!` back to the new status, as in the "goes back to local_testing" example).
- `spec/services/ai_cli/output_spec.rb`: every marker method, incl. missing marker, case, and last-match-wins.
- `spec/services/prompts/stage_prompt_spec.rb`: the default body is used when no template is assigned.
- Handlers and decisions: `spec/services/stages/completion_handler_spec.rb` (finish handlers, `AI_RUN_RESET` cleared, logged actions), `failure_handler_spec.rb`, `pr_check_decision_spec.rb`, `local_test_policy_spec.rb`, `review_handoff_spec.rb`; polling in `spec/services/ai_cli/run_poller_spec.rb`; resolver maps in `spec/models/workflows/stage_resolver_spec.rb`. Prefer extracting new finish logic into a small testable object like these.
- `spec/services/stage_executor_spec.rb` covers dispatch, `start_ai_run` and the rescue path. Stub the agent CLI, `Github::Client` and `Git::*` and assert the resulting `status`, cleared `Workflow::AI_RUN_RESET`, and logged actions.
