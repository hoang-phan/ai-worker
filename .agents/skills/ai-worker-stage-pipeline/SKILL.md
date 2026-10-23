---
name: ai-worker-stage-pipeline
description: Applies ai-worker's stage execution discipline. Use for any task touching app/services/stage_executor.rb, app/services/stages/** (except run_tooling.rb) or spec/services/stage_executor_spec.rb / spec/services/stages/**.
---

# ai-worker stage pipeline

This layer executes one workflow stage at a time: it starts or polls a detached run, turns its completed output into the next workflow state, and records the auditable `StageRun` history. Read the affected file before changing it; this map describes the current seams, not a substitute for the code.

Scope: `app/services/stage_executor.rb`, `app/services/stages/**` except `run_tooling.rb`, and their service specs. `Stages::RunTooling`, detached launch mechanics, and polling live in `ai-worker-agent-cli`; adding or renaming a stage type follows `ai-worker-stage-types`; scheduler eligibility/capacity is `ai-worker-scheduling`; prompt construction is `ai-worker-prompts`; and Git/GitHub clients are `ai-worker-git-github`.

## File map

- `app/services/stage_executor.rb` — guards against the live checkout, starts a non-processing stage through `StartHandler`, or polls its configured run; persists poller log offsets, dispatches completed output to `ConflictResolutionFinish` or `CompletionHandler`, and is the single rescue point for typed command errors and `ArgumentError`.
- `app/services/stages/run_provider.rb` — `Stages::RunProvider.new(workflow:, stage:)`: which agent CLI a stage runs on (`override`, `name`, `provider`); used by `AiRunLauncher` and `Prompts::StagePrompt`. Order in `ai-worker-agent-cli`.
- `app/services/stages/ai_run_launcher.rb` — starts the injected runner, persists the workflow's detached-run pid/log/start/offset state, and logs the supplied start action.
- `app/services/stages/browser_test_start.rb` — validates a UAT/local `BrowserTestRun`, checks out the PR branch for local testing, then launches the browser-configured prompt with its MCP config, environment, and tool restrictions.
- `app/services/stages/ci_check_finish.rb` — moves a completed CI command to `ci_verifying`, stores its log path and exit status, and logs the output tail.
- `app/services/stages/ci_verify_finish.rb` — parses `CI_VERDICT`, either advances to local testing/review and hands off reviewers, or returns to CI checking (or errors after the configured round limit).
- `app/services/stages/completion_handler.rb` — dispatches successful completed output by stage type to the corresponding finish service.
- `app/services/stages/conflict_resolution_finish.rb` — verifies a conflict-resolution run committed its merge, aborts and raises if not, otherwise clears its run and immediately launches the review-fix prompt.
- `app/services/stages/failure_handler.rb` — aborts a resolving merge, clears run state without auto-run, logs `failed`, and parks workflows at the supplied consecutive-failure threshold.
- `app/services/stages/implementation_finish.rb` — delegates a successful implementation result to `PrOpenedFinish` with the implementation action.
- `app/services/stages/jira_update_finish.rb` — parses `JIRA_RESULT` and completes `jira_update`, optionally scheduling delayed UAT.
- `app/services/stages/uat_test_finish.rb` — parses `UAT_RESULT` and completes `uat_test`.
- `app/services/stages/local_test_finish.rb` — parses a local-test result, applies retry policy and feedback, completes into review, then best-effort enables auto-merge or notifies reviewers.
- `app/services/stages/local_test_policy.rb` — holds pure local-test retest, exhaustion, auto-merge, and feedback fallback decisions.
- `app/services/stages/merge_check.rb` — on idle scheduler ticks, marks a merged tracked PR workflow as `merged`; logs GitHub lookup failures without raising.
- `app/services/stages/pr_check_decision.rb` — pure decision logic that turns review state, local-test feedback, and lazy CI failure lookup into approved, changes-requested, or pending plus log actions.
- `app/services/stages/pr_check_finish.rb` — requests review after a fix, chooses whether local testing must rerun, completes the run, and best-effort notifies reviewers when no retest is needed.
- `app/services/stages/pr_check_run.rb` — closes already-merged/approved PRs, logs pure decision actions, or launches a review-fix or conflict-resolution run when changes are requested.
- `app/services/stages/pr_opened_finish.rb` — finds and records the PR URL, chooses CI/local-test/review next state, completes the run, and performs the applicable best-effort handoff.
- `app/services/stages/pr_review_finish.rb` — completes a successful PR-review run into `done` and logs the review output.
- `app/services/stages/pr_review_start.rb` — skips closed PRs or checks out an open PR's head (including cross-repository PRs) before launching its review prompt.
- `app/services/stages/review_handoff.rb` — best-effort reviewer notification and auto-merge work; catches notification/GitHub errors and logs them instead of failing a completed stage.
- `app/services/stages/run_tooling.rb` — selects the detached agent or CI runner/poller pair; it is owned by `ai-worker-agent-cli`, not this layer.
- `app/services/stages/runbook_step_finish.rb` — requires message stages to confirm posting, saves output variables and waiting state, then optionally advances and enqueues the workflow. Runbook lifecycle and invariants: `ai-worker-runbooks`.
- `app/services/stages/simple_implementation_finish.rb` — completes a ci-loop implementation run into `opening_pr` and logs its output.
- `app/services/stages/start_handler.rb` — dispatches every stage type's start path, including branch setup, PR checking, browser tests, CI commands, and runbook gating, using injected collaborators.
- `app/services/stages/follow_up_importer.rb` — creates pending development workflows from FOLLOW_UPS proposals.
- `app/services/stages/task_finish.rb` — completes a task workflow into `done`, then best-effort queues agent-proposed follow-ups (via `follow_up_importer.rb`, which owns the cap of 2, dedupe via `Workflows::SummaryKey`, and the pending workflow build) and pushes its commits, logging each outcome.
- `app/services/stages/workflow_run_gate.rb` — gates a runbook step on the newest relevant GitHub Actions run, logging pass/wait once and raising for a failed run.

## Conventions

- **Inject collaborators by keyword with production defaults.** Executors, starts, finishes, and decisions accept keyword collaborators (`github:`, `git:`, `launcher:`, `handoff:`, `enqueue:` and similar) so specs can pass doubles; keep I/O out of pure decision objects.
- **`StageExecutor` is the single rescue point.** Let `Git::CommandError`, `Github::CommandError`, `AiCli::CommandError`, and configuration `ArgumentError` propagate from pipeline services to `StageExecutor#call`, which delegates failure state to `FailureHandler`; do not add competing broad rescues.
- **Log through the stage.** Every outcome uses `stage.log_run!`; its action must already be in `StageRun::ACTIONS` (see `ai-worker-domain`). Do not create `stage_runs` directly.
- **Every successful run clears its tracked state.** Each success path calls `workflow.finish_ai_run!` before it reaches a terminal or next workflow state; `ConflictResolutionFinish` clears the completed run before launching its replacement run.
- **Follow-ups are best effort.** Work after a successful completion such as review notification, auto-merge, or task push must rescue its expected failure, log it, and never re-fail the completed stage.
- **Runs remain detached.** This layer asks the injected launcher/poller to start or poll; it never waits for a process. Launch/poll implementation and run state mechanics are in `ai-worker-agent-cli`.

## Specs

- Run `RAILS_ENV=test bundle exec rspec spec/services/stage_executor_spec.rb spec/services/stages`.
- `spec/services/stage_executor_spec.rb` covers the live-checkout guard, start/poll routing, persisted log offset, completion dispatch, and single rescue path.
- `spec/services/stages/ai_run_launcher_spec.rb`, `browser_test_start_spec.rb`, `start_handler_spec.rb`, and `pr_review_start_spec.rb` cover start-path state and injected launchers.
- `spec/services/stages/completion_handler_spec.rb`, `conflict_resolution_finish_spec.rb`, `failure_handler_spec.rb`, and every `*_finish_spec.rb` cover completion/failure transitions and logged actions.
- `spec/services/stages/pr_check_decision_spec.rb`, `pr_check_run_spec.rb`, `local_test_policy_spec.rb`, `workflow_run_gate_spec.rb`, and `merge_check_spec.rb` cover decisions and non-launching gates/checks; `review_handoff_spec.rb` covers swallowed follow-up failures.
- `spec/services/stages/run_tooling_spec.rb` belongs to `ai-worker-agent-cli`, even though it sits beside these specs.
