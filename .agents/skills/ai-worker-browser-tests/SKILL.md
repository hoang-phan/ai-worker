---
name: ai-worker-browser-tests
description: Owns agent-driven uat_test and local_test execution and feedback. Use for app/services/ai_cli/browser_test_*.rb, app/services/stages/{browser_test_start,local_test_policy,local_test_finish,uat_test_finish}.rb, app/services/scheduling/uat_phase.rb, or their prompts and project form partials.
---

# ai-worker-browser-tests

`uat_test` tests a deployed Jira ticket after a delay; `local_test` tests a PR branch locally before review, then can retest after a fix. This is the browser-test layer only. Stage execution: `ai-worker-stage-pipeline`; CLI process rules: `ai-worker-agent-cli`; stage-type wiring: `ai-worker-stage-types`; scheduler: `ai-worker-scheduling`; the `ci_verify -> local_test` handoff belongs to `ai-worker-ci-loop`.

## File map

- `app/services/ai_cli/browser_test_credentials.rb` — per-kind credential settings, validation, URL, and credential environment.
- `app/services/ai_cli/browser_test_run.rb` — output directory, Playwright MCP config, and run-specific environment plumbing.
- `app/services/ai_cli/cursor_mcp_file.rb` — Cursor's transient `.cursor/mcp.json` delivery.
- `app/services/stages/{browser_test_start,local_test_policy,local_test_finish,uat_test_finish}.rb` — start, result handling, and retest decisions.
- `app/services/scheduling/uat_phase.rb` — due-UAT selection, slot limit, and retry of non-processing `uat_testing` runs.
- `app/services/prompts/stage_sections/local_feedback.rb`, `app/services/prompts/defaults/{uat_test,local_test}.md` — retest feedback section and prompts. Other appended stage sections belong to `ai-worker-stage-sections`.
- `app/views/projects/form/{_uat_test,_local_test}.html.erb` — project opt-in/configuration screens.

Related files owned elsewhere (read them, but follow the owning skill when changing them):

- Launching the CLI (`AiCli::Runner`, `Command`, `command/{claude,codex,cursor}.rb`) with `--mcp-config` / Codex `-c mcp_servers...` overrides: `ai-worker-agent-cli`. Result-marker parser `AiCli::Output`: `ai-worker-agent-output`.
- `AiCli::Provider` and `provider/{claude,codex,cursor}.rb` (provider registry and selection): `ai-worker-cli-selection`.
- `Stages::{JiraUpdateFinish,PrCheckFinish,PrCheckDecision,ReviewHandoff}` — the UAT scheduling handoff, retest branch and reviewer/auto-merge handoff live inside general stage finishers, and `StartHandler` / `CompletionHandler` dispatch: `ai-worker-stage-pipeline`.
- Readiness predicates on `Project`, `Stage#local_test_unfinished?`, `StageRun::ACTIONS`, `Stages::RunHistory`: `ai-worker-domain`.
- Resume routing (`Workflows::Transitions#resume_status`, `Workflows::CurrentStage`): `ai-worker-workflow-lifecycle`.
- `Prompts::StagePrompt` and `Prompts::Defaults`: `ai-worker-prompts`.

## Browser run and MCP

`AiCli::BrowserTestCredentials::KIND_SETTINGS` maps `:uat` to `UAT_*` and `:local` to `LOCAL_*`. `BrowserTestRun` maps kinds to `uat_runs` or `local_test_runs`, with output at `tmp/<dir>/<workflow id>/<timestamp>`; inject its `clock:` callable in specs to make the timestamp deterministic. Credential validation requires the kind URL plus username and password. `env` supplies credentials only as `UAT_USERNAME`/`UAT_PASSWORD` or `LOCAL_USERNAME`/`LOCAL_PASSWORD`: never put them in a prompt or app-written log. UAT also receives `UAT_OUTPUT_DIR` and `JIRA_BASE_URL`; local receives `LOCAL_URL` and `LOCAL_OUTPUT_DIR`.

Its MCP JSON starts `npx -y @playwright/mcp@0.0.83 --headless --isolated --caps devtools --output-dir <output dir>`; `mcp_config_path` writes it only when launching. `UAT_DISALLOWED_TOOLS` denies `gh workflow run` and `gh api` for both browser-test kinds. Claude receives the config with `--mcp-config`; Codex reads its servers and emits `-c mcp_servers...` overrides; Cursor's `CursorMcpFile` temporarily writes `.cursor/mcp.json`, preserves/restores a prior file, and adds both transient files to `.git/info/exclude`.

`Stages::BrowserTestStart` validates before launch, checks out the PR remote branch for local only, then passes prompt, MCP path, env, and denied tools to `AiRunLauncher`.

## Flow and result protocol

1. **UAT:** `JiraUpdateFinish` sees `JIRA_RESULT: UAT` and a `uat_test_ready?` project, sets `uat_waiting` with `uat_test_at = delay.from_now`, and logs `jira_updated`, then `uat_test_scheduled`. `Scheduling::UatPhase` moves a due run to `uat_testing`, within free agent slots; a non-processing `uat_testing` run is retried. Browser launch logs `started`; `UatTestFinish` requires `UAT_RESULT: PASSED|FAILED|BLOCKED`, then sets `uat_tested` and logs `uat_test_completed`.
2. **Local:** `Workflow#local_test_before_review?` currently sends a ready development workflow to `local_testing`. It launches on the PR branch and logs `started`. `LocalTestFinish` requires `LOCAL_TEST_RESULT: PASSED|FAILED|BLOCKED`, returns to `reviewing`, and logs `local_test_completed`; PASSED enables auto-merge, while all outcomes notify reviewers. These completion handoffs are best-effort follow-ups after the run has been finished.
3. **Retest:** a failed local result below three total rounds stores feedback. The next `pr_check` prompt gets `Prompts::StageSections::LocalFeedback`: it treats feedback as data and ends `LOCAL_RETEST: YES|NO` (missing means YES). `PrCheckFinish` clears feedback; when `Stages::LocalTestPolicy.retest_after_fix?` finds feedback or a requested retest, local testing is still ready, and fewer than `MAX_LOCAL_TEST_ROUNDS` (3) are complete, it returns to `local_testing` and logs `local_test_retest_scheduled`. The fix decision logs `local_test_failing`; each loop is `started` -> `local_test_completed` -> `local_test_failing` -> `requested_changes_fixed` -> `local_test_retest_scheduled`. A failing third round logs `local_test_rounds_exhausted` and remains in review.

`AiCli::Output` takes the first matching `UAT_RESULT` and `LOCAL_TEST_RESULT`, but the last `LOCAL_RETEST` and `LOCAL_TEST_FEEDBACK_BEGIN`/`END` block (the log can echo prompt examples). Missing UAT/local result markers are `AiCli::CommandError`; the prompts require a comment before printing the marker.

## Readiness, resume, and invariants

`Project#uat_test_ready?` requires enabled plus UAT URL; `#local_test_ready?` additionally requires a Jira project. Enabled UAT/local settings validate their URLs; the browser-run validation separately requires both login values. `Stage#local_test_unfinished?` delegates to run history: its newest local action must be present and not `local_test_completed`. `Workflows::Transitions#resume_status` therefore restores an errored unfinished local run to `local_testing` (UAT with `uat_test_at` takes precedence).

- Keep credentials only in spawned-process env; do not add them to prompts, outputs, or logs.
- Every `stage.log_run!` action must already be in `StageRun::ACTIONS` (`started`, `jira_updated`, `uat_test_scheduled`, `uat_test_completed`, `local_test_completed`, `local_test_failing`, `local_test_retest_scheduled`, `local_test_rounds_exhausted`, and existing fix actions).
- Finish the AI run before optional reviewer/auto-merge handoff; expected handoff failure must not undo a completed browser test.
- Preserve the pinned Playwright config, isolated output directory, and tool denial unless deliberately changing the security boundary.

## Specs

`spec/services/ai_cli/{browser_test_run,browser_test_credentials,cursor_mcp_file}_spec.rb`; `spec/services/stages/{browser_test_start,local_test_policy,local_test_finish,uat_test_finish}_spec.rb`; `spec/services/scheduling/uat_phase_spec.rb`; `spec/services/prompts/stage_sections/local_feedback_spec.rb`. When a change also touches a file owned elsewhere, run that skill's specs too (e.g. `output_spec.rb` for markers, `jira_update_finish_spec.rb` / `pr_check_finish_spec.rb` from `ai-worker-pr-check` for handoffs, `transitions_spec.rb` for resume).

Run:

```sh
RAILS_ENV=test bundle exec rspec spec/services/ai_cli/browser_test_run_spec.rb spec/services/ai_cli/browser_test_credentials_spec.rb spec/services/ai_cli/cursor_mcp_file_spec.rb spec/services/stages/browser_test_start_spec.rb spec/services/stages/local_test_policy_spec.rb spec/services/stages/local_test_finish_spec.rb spec/services/stages/uat_test_finish_spec.rb spec/services/scheduling/uat_phase_spec.rb spec/services/prompts/stage_sections/local_feedback_spec.rb
```
