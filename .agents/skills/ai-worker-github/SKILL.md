---
name: ai-worker-github
description: Applies ai-worker's GitHub layer discipline. Use for any task touching app/services/github/** or matching specs (spec/services/github/**) — Github::Client, Reader, Writer, PrLocator, Runner, decision helpers, and Github::CommandError.
---

# ai-worker GitHub layer

Every `gh` subprocess runs inside the project's clone (`project.local_directory`) through `Github::Runner`. Read the affected file before changing it; this is a map, not a substitute. Git service ownership is in `ai-worker-git`.

## File map

- `github/client.rb` — `Github::Client.new(project)` is a thin facade (`delegate`) over a reader and writer sharing one `Runner`. It keeps the `FAILED_*` constants; reviewer parsing stays in `Workflow#reviewer_list`. Callers use the facade and specs inject `reader:` / `writer:`. It owns no logic and does **not** own PR lookup.
- `github/reader.rb` — `Github::Reader` is query-only: `pr_url_for_branch`, `find_pr_url` (delegates to `PrLocator`), `pr_info`, `pr_title`, `current_login`, `merged?`, `review_decision`, `checks_failing?`, and `workflow_run_state`.
- `github/review_decision.rb` — `Github::ReviewDecision.call(latest_reviews, reviewers)` selects review state: any assigned reviewer’s approval wins over a change request.
- `github/failing_checks.rb` — `Github::FailingChecks.call(rollup)` checks `statusCheckRollup` for a finished failure and owns `FAILED_CONCLUSIONS` / `FAILED_STATES`; queued or in-progress checks are ignored.
- `github/workflow_run_state.rb` — `Github::WorkflowRunState.call(runs, since:)` selects and maps the newest eligible Actions run.
- `github/pr_locator.rb` — `Github::PrLocator#call(branch_name:, jira_ticket:, output: nil)` read-only lookup order: last PR URL for this repository printed in agent output, then `gh pr view <branch>`, then an open PR whose head branch contains the Jira key. Raise `Github::CommandError` if none is found.
- `github/writer.rb` — `Github::Writer` performs only side effects: `checkout_pr!`, `request_review!` (via `gh api`, without `-R`), and `enable_auto_merge!`.
- `github/runner.rb` — `Github::Runner#run!(argv, scope_to_repo: true, repo:)` appends `-R <repo>` when scoped, runs `Open3.capture3(*argv, chdir: local_directory)`, and translates failures to `Github::CommandError`.
- `github/command_error.rb` — `Github::CommandError < StandardError`.

**PR creation belongs to the agent, not the app.** The implementation prompt directs the agent to run `gh pr create`; app code only finds the result through `find_pr_url`. Do not add `create_pr` to Writer or Client.

## Command and repository rules

- Build an argv array; pass it to `Open3.capture3(*argv, chdir: dir)`. Never interpolate a shell string, use `cd X && ...`, backticks, or `system("...#{x}")`. Ticket text, PR titles, branch names, and reviewer logins are individual argv elements.
- Raise `Github::CommandError` for non-zero exits with command and stderr in the message. Do not rescue inside these objects except intentional lookup fallbacks such as `PrLocator#url_for_head`; `StageExecutor` in `ai-worker-stage-pipeline` records stage failures.
- Run `gh` only through `Github::Runner`. Repository-scoped commands receive `-R <repo>`; `gh api` has no `-R`, so supply the repo in its endpoint and pass `scope_to_repo: false`. `current_login` is also unscoped.

## Specs

- `spec/services/github/reader_spec.rb`, `writer_spec.rb`, and `pr_locator_spec.rb` inject `instance_double(Github::Runner)`, assert exact `run!` argv and keywords, and use an unsaved `Project.new(... repo_full_name: "acme/widgets")`.
- `runner_spec.rb` uses the injected `capture:` seam to assert argv, repository scoping, `chdir:`, and `Github::CommandError` messages. `client_spec.rb` injects `instance_double(Github::Reader/Writer)` into the facade.
- Decision-helper specs cover review precedence, completed failures only, and the newest eligible workflow run. Other code stubs `Github::Client`; never call real `gh`.

Run `RAILS_ENV=test bundle exec rspec spec/services/github` for GitHub-only changes.
