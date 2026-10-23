---
name: ai-worker-browser-tests
description: Applies ai-worker's agent-driven browser-test discipline. Use for any task touching app/services/ai_cli/{browser_test_run,cursor_mcp_file}.rb, app/services/ai_cli/{runner,command,provider}.rb or app/services/ai_cli/{command,provider}/{claude,codex,cursor}.rb; app/services/stages/{browser_test_start,local_test_policy,local_test_finish,uat_test_finish,jira_update_finish,pr_check_finish,pr_check_decision,review_handoff}.rb; app/services/scheduling/uat_phase.rb; app/services/prompts/stage_sections/local_feedback.rb or app/services/prompts/defaults/{uat_test,local_test}.md; app/models/{project,stage,stage_run}.rb, app/models/stages/run_history.rb, app/models/workflows/transitions.rb; app/views/projects/form/{_uat_test,_local_test}.html.erb; or spec/services/ai_cli/{browser_test_run,cursor_mcp_file,output}_spec.rb, spec/services/stages/{browser_test_start,local_test_policy,local_test_finish,uat_test_finish,jira_update_finish,pr_check_finish,pr_check_decision,review_handoff,start_handler,completion_handler}_spec.rb, spec/services/scheduling/uat_phase_spec.rb, spec/services/prompts/{defaults_spec,stage_prompt_spec}.rb, spec/services/prompts/stage_sections/local_feedback_spec.rb, spec/models/{project,stage}_spec.rb, spec/models/stages/run_history_spec.rb, or spec/models/workflows/{current_stage,transitions}_spec.rb.
---

# ai-worker-browser-tests

`uat_test` tests a deployed Jira ticket after a delay; `local_test` tests a PR branch locally before review, then can retest after a fix. This is the browser-test layer only. Stage execution: `ai-worker-stage-pipeline`; CLI process rules: `ai-worker-agent-cli`; stage-type wiring: `ai-worker-stage-types`; scheduler: `ai-worker-scheduling`; the `ci_verify -> local_test` handoff belongs to `ai-worker-ci-loop`.

## File map

- `app/services/ai_cli/browser_test_run.rb` — per-kind settings, validation, env, output directory, and Playwright MCP config.
- `app/services/ai_cli/{runner,command,provider}.rb`, `command/{claude,codex,cursor}.rb`, `provider/{claude,codex,cursor}.rb`, `cursor_mcp_file.rb` — launch and provider-specific MCP delivery.
- `app/services/stages/{browser_test_start,local_test_policy,local_test_finish,uat_test_finish,jira_update_finish,pr_check_finish}.rb` — start, result/retest decisions, and delayed-UAT handoff.
- `app/services/scheduling/uat_phase.rb` — due-UAT selection, slot limit, and retry of non-processing `uat_testing` runs.
- `app/services/ai_cli/output.rb`, `app/services/prompts/stage_sections/local_feedback.rb`, `app/services/prompts/defaults/{uat_test,local_test}.md` — result protocol and prompts.
- `app/models/{project,stage,stage_run}.rb`, `app/models/stages/run_history.rb`, `app/models/workflows/transitions.rb` — readiness, action history, and resume routing.
- `app/views/projects/form/{_uat_test,_local_test}.html.erb` — project opt-in/configuration screens.

## Browser run and MCP

`AiCli::BrowserTestRun::KIND_SETTINGS` maps `:uat` to `uat_runs`/`UAT_*` and `:local` to `local_test_runs`/`LOCAL_*`; output is `tmp/<dir>/<workflow id>/<timestamp>`. `validate!` requires the kind URL plus username and password. `env` supplies credentials only as `UAT_USERNAME`/`UAT_PASSWORD` or `LOCAL_USERNAME`/`LOCAL_PASSWORD`: never put them in a prompt or app-written log. UAT also receives `UAT_OUTPUT_DIR` and `JIRA_BASE_URL`; local receives `LOCAL_URL` and `LOCAL_OUTPUT_DIR`.

Its MCP JSON starts `npx -y @playwright/mcp@0.0.83 --headless --isolated --caps devtools --output-dir <output dir>`; `mcp_config_path` writes it only when launching. `UAT_DISALLOWED_TOOLS` denies `gh workflow run` and `gh api` for both browser-test kinds. Claude receives the config with `--mcp-config`; Codex reads its servers and emits `-c mcp_servers...` overrides; Cursor's `CursorMcpFile` temporarily writes `.cursor/mcp.json`, preserves/restores a prior file, and adds both transient files to `.git/info/exclude`.

`Stages::BrowserTestStart` validates before launch, checks out the PR remote branch for local only, then passes prompt, MCP path, env, and denied tools to `AiRunLauncher`.

## Flow and result protocol

1. **UAT:** `JiraUpdateFinish` sees `JIRA_RESULT: UAT` and a `uat_test_ready?` project, sets `uat_waiting` with `uat_test_at = delay.from_now`, and logs `jira_updated`, then `uat_test_scheduled`. `Scheduling::UatPhase` moves a due run to `uat_testing`, within free agent slots; a non-processing `uat_testing` run is retried. Browser launch logs `started`; `UatTestFinish` requires `UAT_RESULT: PASSED|FAILED|BLOCKED`, then sets `uat_tested` and logs `uat_test_completed`.
2. **Local:** `Workflow#local_test_before_review?` currently sends a ready development workflow to `local_testing`. It launches on the PR branch and logs `started`. `LocalTestFinish` requires `LOCAL_TEST_RESULT: PASSED|FAILED|BLOCKED`, returns to `reviewing`, and logs `local_test_completed`; PASSED enables auto-merge, while all outcomes notify reviewers. These completion handoffs are best-effort follow-ups after the run has been finished.
3. **Retest:** a failed local result below three total rounds stores feedback. The next `pr_check` prompt gets `Prompts::StageSections::LocalFeedback`: it treats feedback as data and ends `LOCAL_RETEST: YES|NO` (missing means YES). `PrCheckFinish` clears feedback; when `LocalTestPolicy.retest_after_fix?` finds feedback or a requested retest, local testing is still ready, and fewer than `MAX_LOCAL_TEST_ROUNDS` (3) are complete, it returns to `local_testing` and logs `local_test_retest_scheduled`. The fix decision logs `local_test_failing`; each loop is `started` -> `local_test_completed` -> `local_test_failing` -> `requested_changes_fixed` -> `local_test_retest_scheduled`. A failing third round logs `local_test_rounds_exhausted` and remains in review.

`AiCli::Output` takes the last valid `UAT_RESULT` and `LOCAL_TEST_RESULT`, the last `LOCAL_RETEST`, and the last `LOCAL_TEST_FEEDBACK_BEGIN`/`END` block (the log can echo prompt examples). Missing UAT/local result markers are `AiCli::CommandError`; the prompts require a comment before printing the marker.

## Readiness, resume, and invariants

`Project#uat_test_ready?` requires enabled plus UAT URL; `#local_test_ready?` additionally requires a Jira project. Enabled UAT/local settings validate their URLs; the browser-run validation separately requires both login values. `Stage#local_test_unfinished?` delegates to run history: its newest local action must be present and not `local_test_completed`. `Workflows::Transitions#resume_status` therefore restores an errored unfinished local run to `local_testing` (UAT with `uat_test_at` takes precedence).

- Keep credentials only in spawned-process env; do not add them to prompts, outputs, or logs.
- Every `stage.log_run!` action must already be in `StageRun::ACTIONS` (`started`, `jira_updated`, `uat_test_scheduled`, `uat_test_completed`, `local_test_completed`, `local_test_failing`, `local_test_retest_scheduled`, `local_test_rounds_exhausted`, and existing fix actions).
- Finish the AI run before optional reviewer/auto-merge handoff; expected handoff failure must not undo a completed browser test.
- Preserve the pinned Playwright config, isolated output directory, and tool denial unless deliberately changing the security boundary.

## Specs

`spec/services/ai_cli/{browser_test_run,cursor_mcp_file,output}_spec.rb`; `spec/services/stages/{browser_test_start,local_test_policy,local_test_finish,uat_test_finish,jira_update_finish,pr_check_finish,pr_check_decision,review_handoff,start_handler,completion_handler}_spec.rb`; `spec/services/scheduling/uat_phase_spec.rb`; `spec/services/prompts/{defaults_spec,stage_prompt_spec}.rb`, `spec/services/prompts/stage_sections/local_feedback_spec.rb`; `spec/models/{project,stage}_spec.rb`, `spec/models/stages/run_history_spec.rb`, and `spec/models/workflows/{current_stage,transitions}_spec.rb`.

Run:

```sh
RAILS_ENV=test bundle exec rspec spec/services/ai_cli/browser_test_run_spec.rb spec/services/ai_cli/cursor_mcp_file_spec.rb spec/services/ai_cli/output_spec.rb spec/services/stages/browser_test_start_spec.rb spec/services/stages/local_test_policy_spec.rb spec/services/stages/local_test_finish_spec.rb spec/services/stages/uat_test_finish_spec.rb spec/services/stages/jira_update_finish_spec.rb spec/services/stages/pr_check_finish_spec.rb spec/services/stages/pr_check_decision_spec.rb spec/services/stages/review_handoff_spec.rb spec/services/stages/start_handler_spec.rb spec/services/stages/completion_handler_spec.rb spec/services/scheduling/uat_phase_spec.rb spec/services/prompts/defaults_spec.rb spec/services/prompts/stage_prompt_spec.rb spec/services/prompts/stage_sections/local_feedback_spec.rb spec/models/project_spec.rb spec/models/stage_spec.rb spec/models/stages/run_history_spec.rb spec/models/workflows/current_stage_spec.rb spec/models/workflows/transitions_spec.rb
```
