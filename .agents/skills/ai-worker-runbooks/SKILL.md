---
name: ai-worker-runbooks
description: Applies ai-worker's runbook workflow discipline (Workflow#kind = runbook). Use for any task touching the runbook parts of app/models/workflows/{runbook_navigator,runbook_clone,stage_seeder,stage_outputs,variables,current_stage,transitions}.rb or app/models/stage.rb, app/services/stages/{runbook_step_finish,workflow_run_gate}.rb, the runbook branch of app/services/stages/start_handler.rb, Prompts::StagePrompt#slack_message, app/controllers/{stages,workflow_runbooks}_controller.rb, app/views/workflows/_stages.html.erb, app/views/workflows/form/_runbook_fields.html.erb, app/views/stages/form/_runbook_fields.html.erb, or spec/models/workflows/runbook_*_spec.rb, spec/services/stages/{runbook_step_finish,workflow_run_gate}_spec.rb, spec/requests/{stages,workflow_runbooks}_spec.rb.
---

# ai-worker-runbooks

A runbook is a workflow with an ordered, user-editable list of `runbook_step` stages (a deployment checklist). Each stage is an agent run, and a person (or `auto_advance`) moves it on. The code wins over `docs/RUNBOOK.md`. Model rules: `ai-worker-domain`; screens: `ai-worker-ui`; stage execution: `ai-worker-stage-pipeline`; scheduler: `ai-worker-scheduling`; placeholders: `ai-worker-prompts`.

## File map

- `app/models/workflows/runbook_navigator.rb` — `start!`, `advance!`, `next_stage`, `previous_stage` (reached via `Workflow#start_runbook!` / `#advance!` / `#previous_runbook_stage`).
- `app/models/workflows/transitions.rb` — `start!` (runbook branch), `resume!`, `can_run_stage?`, `request_stage_run!`, `can_advance?`; its `resume_status` forwards to `Workflows::ResumeStatus`.
- `app/models/workflows/resume_status.rb` — selects the status for an errored workflow to resume; specified in `spec/models/workflows/resume_status_spec.rb`.
- `app/models/workflows/current_stage.rb` — a runbook's current stage is `current_stage_id`, not status-resolved.
- `app/models/workflows/stage_seeder.rb` — `COPIED_RUNBOOK_ATTRIBUTES`: stage columns copied from `copy_stages_from_id`.
- `app/models/workflows/runbook_clone.rb` — Clone button: same stages, `input_variables` only.
- `app/models/workflows/variables.rb` — `NAME=value` text form; `output_names` / `input_only` split user-typed from stage-emitted.
- `app/models/workflows/stage_outputs.rb` — successful (`stage_completed`) outputs, `all` / `latest_for(stage)`.
- `app/models/stage.rb` — `run_mode` (`agent`/`message`, prefix `run`), `name` and `channel` validations, `auto_advance`, `wait_for_workflow`, `removable?`.
- `app/services/stages/start_handler.rb` — `start_runbook_step`: gate, then launch the prompt (wrapped for message stages).
- `app/services/prompts/stage_prompt.rb` — `slack_message` forwards to `Prompts::SlackPost` (`app/services/prompts/slack_post.rb`), which wraps the text in the post-to-Slack instructions.
- `app/services/stages/workflow_run_gate.rb` — `wait_for_workflow` gate on GitHub Actions.
- `app/services/stages/runbook_step_finish.rb` — success path (POSTED check, variables, waiting, auto-advance).
- `app/controllers/workflow_runbooks_controller.rb` — `run_stage`, `advance`, `clone` (routes in `config/routes.rb`); Start is `workflow_transitions#start`.
- `app/controllers/stages_controller.rb` — stage CRUD, runbook-only (`require_runbook`), `destroy` guarded by `removable?`.
- `app/views/workflows/_stages.html.erb`, `workflows/form/_runbook_fields.html.erb`, `stages/form/_runbook_fields.html.erb` — stage table, variables / copy-source form, stage options form.

## Lifecycle

1. **Start** (`Transitions#start!` → `RunbookNavigator#start!`): `current_stage_id` = first stage, `implementing`, `auto_run: false`. No stages → `done`.
2. **Run stage**: the button sets `auto_run: true` and enqueues `WorkflowSchedulerJob` (a runbook is eligible only if `auto_run?` or named; see `ai-worker-scheduling`). `StartHandler#start_runbook_step` first passes `WorkflowRunGate` (no `wait_for_workflow` → passes; otherwise re-checked every tick, logs `waiting_for_check` once, `check_passed` on success, raises `Github::CommandError` if the run failed; only runs started after the previous stage's `started` run count). Then the agent runs `prompt.body`, or `slack_message(prompt.body)` for `message` stages.
3. **Finish** (`RunbookStepFinish`): a message stage whose output has no `POSTED` line (`AiCli::Output#posted?`) raises `AiCli::CommandError`. Otherwise `waiting` + `awaiting_next: true`, `variables` merged with the output's variables, `stage_completed` logged (plus `message_sent` for message stages).
4. **Wait for Next**: `can_advance?` is true only while `awaiting_next?`. `advance!` logs `advanced`, moves `current_stage_id` on with `auto_run: true` and `implementing`, or ends `done` after the last stage.
5. **auto_advance**: `RunbookStepFinish` calls `advance!` itself and re-enqueues the scheduler, so the next stage starts unattended; a stage without it stops until Next, and a failure stops the chain.
6. **Outputs feed later stages**: `VAR: NAME=value` lines and `VAR_BEGIN`/`VAR_END` blocks (parsed by `AiCli::Output#variables`) land in `Workflow#variables`, so later prompts see them as `{NAME}`; `{REPO}` also selects the repo for `wait_for_workflow`.

## Invariants

- The current stage cannot be removed on a started runbook (`Stage#removable?`; the controller redirects with an alert). Pending runbooks can drop any stage.
- Variable names must match `Prompts::Renderer::VARIABLE_NAME` (`Workflow#variable_names_are_placeholders`); `Variables.parse` upcases names.
- Clone copies only user-set variables (`input_variables`); emitted ones are dropped so old results don't leak. Stages are copied through `StageSeeder`, with `stage_type` forced to `runbook_step`.
- Stage lists are runbook-only; `stage_params` permits the runbook columns only for runbooks.
- Message stages require `channel`; every runbook stage requires `name`; `wait_for_workflow` is a workflow file name (format-validated).
- Only `stage_completed` runs count as outputs; failed or started rows never do.

## Adding a runbook stage option

1. Migration (`ai-worker-domain`: new column, append-only enums), then validate it in `app/models/stage.rb`.
2. Add it to `stage_params` in `StagesController` and to `COPIED_RUNBOOK_ATTRIBUTES` (clone/seed would silently drop it otherwise).
3. Add the field to `stages/form/_runbook_fields.html.erb` and, if it matters at a glance, a badge in `workflows/_stages.html.erb`.
4. Act on it in `StartHandler#start_runbook_step` or `RunbookStepFinish` (and `StagePrompt` / placeholders if it changes the prompt, see `ai-worker-prompts`).
5. Specs: the relevant runbook/finish/gate spec, `stages_spec.rb` (params), `runbook_clone_spec.rb` (copied), plus the `ai-worker-testing` rules.
