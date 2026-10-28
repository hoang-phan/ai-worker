---
name: ai-worker-ci-loop
description: Owns the ci_loop stage flow, resumption, prompts, and CI status transitions. Use for app/services/stages/{ci_*,simple_implementation_finish,pr_create_finish,pr_opened_finish}.rb, app/models/workflows/ci_loop_resume.rb, or ci_loop defaults and settings UI.
---

# ai-worker-ci-loop

Scope: the end-to-end `ci_loop` flow of a Jira project: `simple_implementation` -> `pr_create` -> (`ci_check` -> `ci_verify`)* -> `local_testing` / `reviewing`. It is spread over many layers; this skill is the map of how they fit together. The layer rules live in the neighbouring skills and are not repeated: runners/pollers in `ai-worker-agent-cli`, finished-run log parsers (`AiCli::Output` and kin) in `ai-worker-agent-output`, adding stage types/statuses/markers in `ai-worker-stage-types`, the executor/handlers in `ai-worker-stage-pipeline`, model/enum rules in `ai-worker-domain`, templates and placeholders in `ai-worker-prompts`, the project form in `ai-worker-ui`, the scheduler in `ai-worker-scheduling`, specs in `ai-worker-testing`.

Why this order: `bin/ci` posts its result as a required GitHub status for the pushed commit, so the PR (and push) comes before the check. Auto-merge is enabled with the PR but can't merge until the check passes. Reviewers are pinged only once the verify passed.

## Flow

| Status | Stage type | Runs | Finish | StageRun action |
| --- | --- | --- | --- | --- |
| `implementing` | `simple_implementation` | agent: implements and commits, no full gate, no push/PR | `Stages::SimpleImplementationFinish` -> `opening_pr` | `ran_implementation` |
| `opening_pr` | `pr_create` | agent: push, `gh pr create`, review request, Jira | `Stages::PrCreateFinish` -> `ci_checking` | `pr_created` |
| `ci_checking` | `ci_check` | plain command (`bash -lc`), not an agent | `Stages::CiCheckFinish` -> `ci_verifying` | `ci_check_completed` |
| `ci_verifying` | `ci_verify` | agent: reads the log, fixes, commits, pushes, prints `CI_VERDICT` | `Stages::CiVerifyFinish` -> `ci_checking` / `local_testing` / `reviewing` / `errored` | `ci_verify_passed` / `ci_verify_failed` (+ `ci_rounds_exhausted`) |

`pr_check` is seeded too and its shared templates are unchanged; it runs from `reviewing` as in the standard flow.

## File map

- `app/models/project.rb` — ci_loop-specific readiness and settings belong to `ai-worker-domain`.
- `app/models/workflow.rb` — ci_loop statuses and resume/current-stage wiring belong to `ai-worker-workflow-lifecycle`.
- `app/models/stage.rb` — `Stage::STAGE_TYPES` has `ci_check: 8, ci_verify: 9, pr_create: 10, simple_implementation: 11`; `Stage#completed_ci_rounds` delegates to `Stages::RunHistory`; the stage's own `command` overrides `project.ci_command` for the check.
- `app/models/workflows/stage_seeder.rb` — ci_loop seeds five stages only for new ready workflows; see `ai-worker-workflow-lifecycle`.
- `app/models/workflows/stage_resolver.rb` — ci_loop status-to-stage mapping and lazy types belong to `ai-worker-workflow-lifecycle`.
- `app/models/workflows/current_stage.rb` — enables ci_loop resolution for ready development workflows; see `ai-worker-workflow-lifecycle`.
- `app/models/workflows/ci_loop_resume.rb` (`Workflows::CiLoopResume#status`) — where an errored workflow goes back to, from the newest non-`resumed` StageRun: `simple_implementation` `ran_implementation` -> `opening_pr`, else `implementing`; `ci_check` `ci_check_completed` -> `ci_verifying`, else `ci_checking`; `ci_verify` `ci_verify_passed` -> nil, `ci_verify_failed`/`ci_rounds_exhausted` -> `ci_checking`, anything else `ci_verifying`; `pr_create` `pr_created` -> `ci_checking`, else `opening_pr`. nil (not development / not ci_loop / no runs) lets `Workflows::Transitions#resume_status` fall through to its other rules.
- `app/models/stages/run_history.rb` — `Stages::RunHistory#completed_ci_rounds` counts `ci_check_completed` since the newest `resumed`, so a person resuming an exhausted loop gets a fresh budget.
- `app/models/stage_run.rb` — ci_loop audit actions are append-only; see `ai-worker-domain` and `ai-worker-stage-types`.
- `app/services/stages/ci_check_start.rb` — selects `stage.command` or `project.ci_command`, raises when both are blank, then launches the plain CI command.
- `app/services/stages/pr_create_finish.rb` — delegates the completed PR creation to `PrOpenedFinish` with `pr_created` and `project.ci_loop_ready?` as `checks_follow`.
- `app/services/stages/start_handler.rb`, `app/services/stages/completion_handler.rb` — ci_loop dispatch belongs to `ai-worker-stage-pipeline`.
- `app/services/stages/pr_opened_finish.rb` (`Stages::PrOpenedFinish.new(workflow:, stage:, project:, github:, handoff:)#call(output, action:, checks_follow: false)`) — shared with `Stages::ImplementationFinish` (standard flow). Records `github_pr_url` (`github.find_pr_url`); next status is `:ci_checking` when `checks_follow`, else `workflow.post_pr_status`; enables auto-merge unless testing locally; notifies reviewers only when neither testing locally nor `checks_follow`.
- `app/services/stages/simple_implementation_finish.rb` — `finish_ai_run!(status: :opening_pr)`, logs `ran_implementation`.
- `app/services/stages/ci_check_finish.rb` (`#call(exit_status)`) — `finish_ai_run!(status: :ci_verifying, ci_output_path: ai_log_path, ci_exit_status:)`, logs `ci_check_completed` with the exit status and the last `TAIL_BYTES` (3000) of the log. A failing exit is a result, not an error.
- `app/services/stages/ci_verify_finish.rb` (`Stages::CiVerifyFinish.new(workflow:, stage:, project:, handoff:)#call(output)`) — reads `AiCli::Output#ci_verdict` (`CI_VERDICT: PASSED|FAILED`, last marker line, case-insensitive); no marker raises `AiCli::CommandError` (treated as a failed run). PASSED: `finish_ai_run!(status: workflow.post_pr_status)`, `ci_verify_passed`, `handoff.notify_reviewers!` unless testing locally. FAILED: exhausted when the `ci_check` stage's `completed_ci_rounds >= project.ci_max_rounds`; status `errored` if exhausted, else `ci_checking`; logs `ci_verify_failed`, plus `ci_rounds_exhausted` when exhausted.
- `app/services/stages/run_tooling.rb` — `ci_check` selects plain-command tooling; see `ai-worker-agent-cli`.
- `app/services/ci/command_runner.rb`, `app/services/ci/check_poller.rb` — ci-check runner/poller behavior belongs to `ai-worker-agent-cli`.
- `app/services/scheduling/workflow_queries.rb` — ci_loop active/busy status scheduling belongs to `ai-worker-scheduling`.
- `app/services/prompts/defaults/{simple_implementation,ci_verify,pr_create}.md` (registered in `Prompts::Defaults::DESCRIPTIONS`, used when no `PromptTemplate` of that stage type exists):
  - `simple_implementation.md`: `{SKILLS}`, `{JIRA}`; tells the agent not to run the full gate, push, open a PR or touch Jira, and to commit everything.
  - `ci_verify.md`: `{CI_COMMAND}`, `{JIRA}`, `{CI_STATUS}` (= `workflow.ci_exit_status`), `{CI_OUTPUT}` (= `workflow.ci_output_path`), `{CI_VERIFY_INSTRUCTIONS}` (= `project.ci_verify_instructions`); never runs the whole gate, fixes every failure, commits and `git push origin HEAD`, ends with exactly one `CI_VERDICT: PASSED` / `CI_VERDICT: FAILED` line.
  - `pr_create.md`: `{PR_SKILLS}` (= `workflow.pr_skills`), `{JIRA}`, `{REVIEWER}`, `{PR_INSTRUCTIONS}` (= `project.pr_instructions`); pushes, `gh pr create`, requests review, updates Jira, prints the PR URL on its own line (read by `github.find_pr_url`).
  - `app/services/prompts/{project_placeholders,workflow_placeholders}.rb` — ci_loop placeholder tokens belong to `ai-worker-prompts`.
- `app/views/projects/form/_ci_loop.html.erb` — the "Workflow flow (Jira projects)" fieldset (rendered from `app/views/projects/_form.html.erb`): `flow` select, `ci_command`, `ci_max_rounds` (1-20), `ci_verify_instructions`, `pr_instructions`. `default_pr_skills` is in `_form.html.erb` itself; `app/views/workflows/form/_jira_fields.html.erb` shows per-workflow `pr_skills` only when `project.ci_loop_ready?`.
- `docs/RUNBOOK.md` — the ci_loop paragraph (status list); keep it in step with the table above.

## Invariants / conventions

- Gate on `Project#ci_loop_ready?` (never `flow_ci_loop?` alone) and, for workflows, `workflow.development?`. A ci_loop project without `jira?` is invalid.
- Don't add a second path to the review ping: reviewers are notified exactly once, by `CiVerifyFinish` on PASSED (or `LocalTestFinish` when testing locally). `PrOpenedFinish` must keep `checks_follow` suppressing it.
- The verify agent must commit and push every fix before finishing: the next check runs on the committed HEAD and posts its status only for a pushed commit. Keep that in `ci_verify.md`.
- `ci_check` is plain code, never an agent: command from `stage.command` else `project.ci_command`, run through `Stages::RunTooling`. A non-zero exit is data (`ci_exit_status`), only a timeout or unknown status raises.
- The round limit is `project.ci_max_rounds` counted by `completed_ci_rounds` (since the last `resumed`); both the finish service and the resume logic depend on the `ci_check_completed` / `resumed` action names, so changing one means changing `RunHistory` and `CiLoopResume`.
- Enum integers and `StageRun::ACTIONS` are append-only. New ci_loop stage types or markers follow the `ai-worker-stage-types` checklist, and must be added to `LAZY_STAGE_TYPES`.
- Seeding is create-time only; never rewrite stages of existing workflows when `flow` changes.
- Behaviour changes to this flow update `docs/RUNBOOK.md` and, if the placeholders change, `docs/PROMPT_TEMPLATES.md`.

## Specs

- Helper: `spec/support/ci_loop_helper.rb` (`build_ci_project(**attrs)` -> Jira project with `flow: :ci_loop, ci_command: "bin/ci"`; `build_ci_workflow(project, **attrs)` -> `implementing`, branch `ci-branch`), built on `RecordHelper` (`build_jira_project`, `build_jira_workflow`). Use it instead of hand-built records.
- Models: `spec/models/workflows/{stage_seeder,stage_resolver,current_stage,ci_loop_resume}_spec.rb`, `spec/models/stages/run_history_spec.rb`, `spec/models/workflow_spec.rb`.
- Services: `spec/services/stages/{ci_check_start,simple_implementation_finish,pr_create_finish,pr_opened_finish,ci_check_finish,ci_verify_finish,run_tooling,completion_handler}_spec.rb`, `spec/services/ci/{command_runner,check_poller}_spec.rb`, `spec/services/scheduling/workflow_queries_spec.rb`, `spec/services/stage_executor_spec.rb`, `spec/services/ai_cli/output_spec.rb` (`ci_verdict`).
- Prompts: `spec/services/prompts/stage_prompt/ci_loop_spec.rb`, `spec/services/prompts/defaults_spec.rb`, `spec/services/prompts/project_placeholders_spec.rb`.
- Run with `RAILS_ENV=test bundle exec rspec spec/models/workflows spec/models/stages spec/services/stages spec/services/ci spec/services/prompts/stage_prompt/ci_loop_spec.rb spec/services/scheduling/workflow_queries_spec.rb`.
