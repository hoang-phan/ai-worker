---
name: ai-worker-pr-check
description: Applies ai-worker's pr_check review-cycle discipline. Use for any task touching app/services/stages/{pr_check_run,pr_check_decision,pr_check_finish,review_handoff,merge_check}.rb or their specs.
---

# ai-worker pr check

This subsystem owns the review cycle for this app's own pull requests: inspect review and check state, launch fixes when needed, hand completed fixes back to reviewers, and notice later merges. Read the affected file before changing it; this map describes the current seams, not a substitute for the code.

## File map

- `app/services/stages/pr_check_run.rb` — closes already-merged or approved PRs, logs pure decision actions, or merges main and launches a review-fix or conflict-resolution run when changes are requested.
- `app/services/stages/pr_check_decision.rb` — pure decision logic that turns review state, local-test feedback, and lazy CI failure lookup into approved, changes-requested, or pending plus ordered log actions.
- `app/services/stages/pr_check_finish.rb` — requests review after a fix, chooses whether local testing must rerun, completes the run, best-effort records agent lessons, and notifies reviewers when no retest is needed.
- `app/services/stages/review_handoff.rb` — best-effort reviewer notification and auto-merge work; catches notification or GitHub errors and logs them instead of failing a completed stage.
- `app/services/stages/merge_check.rb` — on idle scheduler ticks, marks a merged tracked PR workflow as `merged`; logs GitHub lookup failures without raising.

## Conventions

- **Keep `PrCheckDecision` pure.** It receives the review decision, local-test state, and lazy check-failure callable; it does not access workflows, Git, or GitHub. Consult CI only while an approval remains possible, and return the ordered stage actions for the caller to log.
- **Launch the right fix path.** `PrCheckRun` updates the branch with main before launching a requested-changes fix: a conflict launches `Prompts::StagePrompt::CONFLICT` with `conflict_resolution_started`; a clean update launches the review-fix prompt. Git and GitHub errors propagate to the pipeline's single rescue point.
- **Use the local-retest policy after a fix.** `PrCheckFinish` clears local-test feedback and uses `Stages::LocalTestPolicy.retest_after_fix?` with project readiness, completed local-test rounds, pending feedback, and the agent's `LOCAL_RETEST` marker. A retest moves to `local_testing`; otherwise it stays reviewing and notifies reviewers with the fixed summary.
- **Keep review handoffs best effort.** `ReviewHandoff` notification and auto-merge failures are logged through the stage and never re-fail a completed stage. Notification collects completed pings before reading the current thread timestamp.
- **Record agent lessons best effort.** A failure to save parsed lessons logs a warning and cannot fail the review-fix completion.
- **Run merge checks only on idle ticks.** `MergeCheck` detects a PR merged after the workflow reached `done`; GitHub lookup failures are logged and retried on a later idle tick.

## Specs

- Run review-cycle coverage with `RAILS_ENV=test bundle exec rspec spec/services/stages/{pr_check_run,pr_check_decision,pr_check_finish,review_handoff,merge_check}_spec.rb`.
- `pr_check_run_spec.rb` covers merged and approved closure, pending decisions, ordered decision logging, review-fix versus conflict-resolution launch, and propagated Git errors.
- `pr_check_decision_spec.rb` covers review/local-test/check combinations and lazy CI lookup.
- `pr_check_finish_spec.rb` covers review requests, local-retest choice, reviewer notification, feedback clearing, and best-effort agent lessons.
- `review_handoff_spec.rb` covers notification labels and threads plus swallowed notifier/GitHub failures and auto-merge outcomes.
- `merge_check_spec.rb` covers idle merged detection and logged GitHub failures.
