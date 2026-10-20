---
name: ai-worker-stage-types
description: Checklist for adding, renaming or changing an ai-worker stage type, a Workflow status, or an agent result marker line (e.g. LOCAL_TEST_RESULT). Use when a change spans Stage, StageRun::ACTIONS, Workflow, StageExecutor, prompts, AiCli::Output and the scheduler together — uat_test and local_test are the worked examples.
---

# ai-worker-stage-types

A stage type crosses models, services, jobs and views, and is easy to get half-right. Follow the checklist in order. Per-layer rules live elsewhere: `ai-worker-domain` (models, migrations), `ai-worker-orchestration` (jobs/services), `ai-worker-testing` (specs), `ai-worker-ui` (views). This file only lists the touch points. Worked example throughout: `local_test`.

## Lifecycle

`Workflow#status` -> `Workflow#current_stage` (via `STAGE_TYPE_BY_STATUS`) -> `StageExecutor#call` dispatches on `stage.stage_type` to a `start_*` method -> `start_ai_run` spawns a detached agent (`processing: true`, pid/log in `ai_*` columns) -> later scheduler ticks hit `StageExecutor#poll_ai_run` -> when done, `finalize_success` dispatches to a finish handler -> handler writes `ai_run_attrs.merge(status: <next>)`, logs a `StageRun` action, runs side effects.

local_test: `implementing` -> (`finalize_success` "implementation" sets `local_testing` when `project.local_test_ready?`) -> `start_local_test` -> `finish_local_test` -> `reviewing`. A failed round feeds `local_test_feedback` to the next `pr_check` run, which may send the workflow back to `local_testing` (`local_retest?`).

## Checklist (in order)

1. **Migration/enum values** (see `ai-worker-domain`). Enum integers are stored: append, never renumber.
   - `Stage` `enum :stage_type` in `app/models/stage.rb` **and the duplicate** `enum :stage_type` in `app/models/prompt_template.rb` (keep identical).
   - `Workflow` `enum :status` in `app/models/workflow.rb` (`local_testing: 11`).
2. **`StageRun::ACTIONS`** (`app/models/stage_run.rb`): add every action the new code will `log(...)`. Validation rejects unknown actions, so this comes before any handler code (`local_test_completed`, `local_test_failing`, `local_test_retest_scheduled`, `local_test_rounds_exhausted`).
3. **Stage helpers** (`app/models/stage.rb`): history queries the flow needs, e.g. `completed_local_test_rounds`, `local_test_unfinished?`. Use `last_action` (ordered by id), not the association's default `created_at desc` order.
4. **Workflow wiring** (`app/models/workflow.rb`):
   - `STAGE_TYPE_BY_STATUS` (jira projects). Also `SIMPLE_STAGE_TYPE_BY_STATUS` (personal) / `PR_REVIEW_STAGE_TYPE_BY_STATUS` only if those kinds reach the stage.
   - `current_stage`: a stage type not seeded at creation must be in the `find_or_create_by!` list (`%w[jira_update uat_test local_test]`), otherwise it returns nil and the scheduler silently skips the workflow.
   - `seed_stages`: only add the type here if every new workflow needs it up front (local_test is lazily created instead).
   - `resume_status`: where an `errored` workflow returns to (`:uat_testing`, `:local_testing` via private `local_test_unfinished?`). Without it a failure resumes into the wrong status.
5. **Prompt default** (`app/models/prompt_template.rb`): `DEFAULT_<TYPE>_BODY` constant, then in `Prompts::StagePrompt#body` (`app/services/prompts/stage_prompt.rb`) add `text ||= PromptTemplate::DEFAULT_LOCAL_TEST_BODY if stage.local_test?`. Placeholders are rendered by `Prompts::Renderer`.
6. **Result marker** (`app/services/ai_cli/output.rb`): one method per marker line (`local_test_result`, `retest_requested?`, `local_test_feedback_block`), anchored regex, take the **last** match (the log echoes the prompt's own example). The prompt body must tell the agent to print the exact marker.
7. **Start path** (`app/services/stage_executor.rb`): add a `when "local_test" then start_local_test` arm in `#call`, and the `start_*` method. Validate config first (`AiCli::BrowserTestRun#validate!` raises `AiCli::CommandError`, handled by `fail_stage`), then `start_ai_run` (or `start_browser_test`).
8. **Finish handler**: add a `when` arm in `#finalize_success` and a `finish_*` method (`finish_local_test`). Parse the marker; a missing marker raises `AiCli::CommandError` so the stage fails visibly.
9. **Scheduler** (`app/jobs/workflow_scheduler_job.rb`): add the new in-flight status to `run_active_workflows`'s `Workflow.where(status: [...])` (or the `updating` list for statuses entered outside the main loop, or a phase like `run_uat_phase` for time-gated ones), and to `work_in_progress?` if the post-merge phase must not run during it.
10. **Views/controllers**: add the status to the badge `case` in `app/views/workflows/show.html.erb` and `app/views/projects/show.html.erb` (`badge-info` / `badge-success`). Project-level toggles/fields go in `app/views/projects/_form.html.erb` and `ProjectsController#project_params`, plus `Project#local_test_ready?`-style readiness predicate. `PromptTemplate` forms list types from the enum automatically.

## Invariants

- Every logged action is in `StageRun::ACTIONS` first (step 2).
- Every finish handler's `workflow.update!` merges `Workflow::AI_RUN_RESET` (clears `processing`, pid, log path, offset). Forget it and the workflow polls a dead run forever. `fail_stage` already does this; only the success paths are yours.
- A finish handler leaves the workflow in a status the scheduler picks up (or terminal). Check the status appears in step 9's lists.
- Counting rounds/retries: cap them (`MAX_LOCAL_TEST_ROUNDS`) and log an `_exhausted` action rather than looping.
- New result markers get an `AiCli::Output` method **and** a spec; never regex agent output inline in `StageExecutor`.
- Handler-side effects that reach git/GitHub/Slack follow `ai-worker-orchestration` (argv arrays, rescue the typed `*::CommandError`).

## Specs to add (see `ai-worker-testing`)

- Model: `spec/models/stage_spec.rb` (helpers), `spec/models/workflow_spec.rb` (`current_stage` creating the stage, `resume_status`/`resume!` back to the new status, as in the "goes back to local_testing" example).
- `spec/services/ai_cli/output_spec.rb`: every marker method, incl. missing marker, case, and last-match-wins.
- `spec/services/prompts/stage_prompt_spec.rb`: the default body is used when no template is assigned.
- StageExecutor-level: there is no `spec/services/stage_executor_spec.rb` yet. Decisions are being extracted into small testable objects (`spec/services/stages/pr_check_decision_spec.rb`, `spec/services/ai_cli/run_poller_spec.rb`); prefer extracting new finish logic the same way. If you add an executor spec, stub the agent CLI, `Github::Client` and `Git::*` and assert the resulting `status`, cleared `Workflow::AI_RUN_RESET`, and logged actions.
