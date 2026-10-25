---
name: ai-worker-stage-pipeline
description: Applies ai-worker's stage execution discipline. Use for any task touching app/services/stage_executor.rb or the generic stage machinery under app/services/stages/** (and their specs). Specialised stage files (ci_loop, browser tests, runbooks, PR-review, run_tooling, run_provider) belong to narrower skills; this skill remains the fallback owner for app/services/stages/**.
---

# ai-worker stage pipeline

This layer executes one workflow stage at a time: it starts or polls a detached run, turns its completed output into the next workflow state, and records the auditable `StageRun` history. Read the affected file before changing it; this map describes the current seams, not a substitute for the code.

Core scope: `app/services/stage_executor.rb` and the generic handlers listed below. Detached launch/poll mechanics live in `ai-worker-agent-cli`; adding or renaming a stage type follows `ai-worker-stage-types`; scheduler eligibility/capacity is `ai-worker-scheduling`; prompt construction is `ai-worker-prompts`; Git/GitHub clients are `ai-worker-git-github`.

## File map

- `app/services/stage_executor.rb` — guards against the live checkout, starts a non-processing stage through `StartHandler`, or polls its configured run; dispatches completed output to `ConflictResolutionFinish` or `CompletionHandler`, and is the single rescue point for typed command errors and `ArgumentError`.
- `app/services/stages/ai_run_poll.rb` — builds the configured poller from persisted workflow run state, durably advances its log offset even on errors, and returns completed output.
- `app/services/stages/start_handler.rb` — dispatches every stage type's start path, including branch setup, PR checking, browser tests, CI commands, and runbook gating, using injected collaborators.
- `app/services/stages/completion_handler.rb` — dispatches successful completed output by stage type to the corresponding finish service, including specialised finish services.
- `app/services/stages/failure_handler.rb` — aborts a resolving merge, clears run state without auto-run, logs `failed`, and parks workflows at the supplied consecutive-failure threshold.
- `app/services/stages/ai_run_launcher.rb` — resolves the provider via `RunProvider`, starts the injected runner, persists the workflow's detached-run pid/log/start/offset/`ai_provider` state, and logs the supplied start action.
- `app/services/stages/conflict_resolution_finish.rb` — verifies a conflict-resolution run committed its merge, aborts and raises if not, otherwise clears its run and immediately launches the review-fix prompt.
- `app/services/stages/implementation_finish.rb` — delegates a successful implementation result to `PrOpenedFinish` with the implementation action.
- `app/services/stages/pr_check_run.rb` — closes already-merged/approved PRs, logs pure decision actions, or launches a review-fix or conflict-resolution run when changes are requested.
- `app/services/stages/pr_check_decision.rb` — pure decision logic that turns review state, local-test feedback, and lazy CI failure lookup into approved, changes-requested, or pending plus log actions.
- `app/services/stages/pr_check_finish.rb` — requests review after a fix, chooses whether local testing must rerun, completes the run, best-effort records agent lessons, and notifies reviewers when no retest is needed.
- `app/services/stages/review_handoff.rb` — best-effort reviewer notification and auto-merge work; catches notification/GitHub errors and logs them instead of failing a completed stage.
- `app/services/stages/merge_check.rb` — on idle scheduler ticks, marks a merged tracked PR workflow as `merged`; logs GitHub lookup failures without raising.
- `app/services/stages/task_finish.rb` — completes a task workflow into `done`, then best-effort queues agent-proposed follow-ups (via `follow_up_importer.rb`, which owns the cap of 2, dedupe via `Workflows::SummaryKey`, and the workflow build) and pushes its commits, logging each outcome.
- `app/services/stages/follow_up_importer.rb` — creates development workflows from FOLLOW_UPS proposals: `implementing` when `project.brainstorm_auto_start?`, else `pending`.
- `app/services/stages/jira_update_finish.rb` — parses `JIRA_RESULT` and completes `jira_update`, optionally scheduling delayed UAT.

### Owned elsewhere

- `ci_check_start` / `ci_check_finish` / `ci_verify_finish` / `pr_create_finish` / `pr_opened_finish` / `simple_implementation_finish` → `ai-worker-ci-loop`
- `browser_test_start` / `local_test_finish` / `local_test_policy` / `uat_test_finish` → `ai-worker-browser-tests`
- `runbook_step_start` / `runbook_step_finish` / `workflow_run_gate` → `ai-worker-runbooks`
- `pr_review_start` / `pr_review_finish` → `ai-worker-pr-review-workflows`
- `run_tooling` / `run_provider` → `ai-worker-agent-cli` / `ai-worker-cli-selection`

## Conventions

- **Inject collaborators by keyword with production defaults.** Executors, starts, finishes, and decisions accept keyword collaborators (`github:`, `git:`, `launcher:`, `handoff:`, `enqueue:` and similar) so specs can pass doubles; keep I/O out of pure decision objects. For `StageExecutor`, accept `handoff: nil`, memoize it, and construct the production default as `Stages::ReviewHandoff.new(workflow, stage, github: github)` so its auto-merge and PR-title calls share the executor's lazily resolved GitHub client. Forward that same handoff to both `StartHandler` and `CompletionHandler`.
- **`StageExecutor` is the single rescue point.** Let `Git::CommandError`, `Github::CommandError`, `AiCli::CommandError`, and configuration `ArgumentError` propagate from pipeline services to `StageExecutor#call`, which delegates failure state to `FailureHandler`; do not add competing broad rescues.
- **Log through the stage.** Every outcome uses `stage.log_run!`; its action must already be in `StageRun::ACTIONS` (see `ai-worker-domain`). Do not create `stage_runs` directly.
- **Every successful run clears its tracked state.** Each success path calls `workflow.finish_ai_run!` before it reaches a terminal or next workflow state; `ConflictResolutionFinish` clears the completed run before launching its replacement run.
- **Follow-ups are best effort.** Work after a successful completion such as review notification, auto-merge, or task push must rescue its expected failure, log it, and never re-fail the completed stage.
- **Runs remain detached.** This layer asks the injected launcher/poller to start or poll; it never waits for a process. Launch/poll implementation and run state mechanics are in `ai-worker-agent-cli`.

## Specs

- Run core coverage with `RAILS_ENV=test bundle exec rspec spec/services/stage_executor_spec.rb spec/services/stages/{ai_run_launcher,start_handler,completion_handler,failure_handler,conflict_resolution_finish,implementation_finish,pr_check_run,pr_check_decision,pr_check_finish,review_handoff,merge_check,task_finish,follow_up_importer,jira_update_finish}_spec.rb`.
- `spec/services/stage_executor_spec.rb` covers the live-checkout guard, start/poll routing, completion dispatch, and single rescue path.
- `spec/services/stages/ai_run_poll_spec.rb` covers poller construction, running/completed return values, and persisted log offsets.
- `spec/services/stages/ai_run_launcher_spec.rb` and `start_handler_spec.rb` cover start-path state and injected launchers; `start_handler_spec.rb` dispatches every `Stage::STAGE_TYPES` entry and fails if one has no mapped start path.
- `spec/services/stages/completion_handler_spec.rb`, `conflict_resolution_finish_spec.rb`, `failure_handler_spec.rb`, `implementation_finish_spec.rb`, `pr_check_finish_spec.rb`, `jira_update_finish_spec.rb`, and `task_finish_spec.rb` cover completion/failure transitions and logged actions; the completion-handler dispatch guard likewise fails when a stage type has no finisher.
- `spec/services/stages/pr_check_decision_spec.rb`, `pr_check_run_spec.rb`, and `merge_check_spec.rb` cover decisions and non-launching checks; `review_handoff_spec.rb` covers swallowed follow-up failures; `follow_up_importer_spec.rb` covers proposal import.
- Specs for specialised stage files: `ai-worker-ci-loop`, `ai-worker-browser-tests`, `ai-worker-runbooks`, `ai-worker-pr-review-workflows`, `ai-worker-agent-cli`, `ai-worker-cli-selection`.
