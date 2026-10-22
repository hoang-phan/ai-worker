---
name: ai-worker-git-github
description: Applies ai-worker's Git/GitHub layer discipline. Use for any task touching app/services/git/**, app/services/github/**, or their specs (spec/services/git/**, spec/services/github/**) — Git::Shell, Git::BranchService, Github::Client, Reader, Writer, PrLocator, Runner and the CommandError classes.
---

# ai-worker Git / GitHub layer

Every `git` and `gh` subprocess in the app goes through one of these objects, always inside the project's clone (`project.local_directory`). Read the file before changing it; this is a map, not a substitute.

## Git (`app/services/git/`)

- `git/shell.rb` — `Git::Shell.new(directory)`; the only place `git` is spawned.
  - `run(argv)` → `[out, err, status]` via `Open3.capture3(*argv, chdir: directory)`; never raises.
  - `run!(argv)` → stdout, or raises `Git::CommandError` (`"<cmd> failed: <stderr or stdout>"`).
  - `success?(argv)` → boolean from the exit status (probes like `rev-parse --verify`).
  - `checkout!(argv)` → a `git checkout` that, only when stderr matches `would be overwritten by checkout`, runs `git stash push --include-untracked -m "ai-worker: auto-stash ..."` and retries once. Nothing is discarded. Any other failure raises.
- `git/command_error.rb` — `Git::CommandError < StandardError`.
- `git/branch_service.rb` — `Git::BranchService`, built on a `Shell`; class methods wrap instance methods:
  - `create_branch!(project, name)` — checkout + pull `main`, then checkout the branch (create with `-b` if absent locally).
  - `update_with_main!(project, name)` — review-fix flow: same, branch from `origin/<name>` if not local, then merge `main`; returns `:merged` or `:conflict` (conflicted merge left in place for the agent). Any other merge failure aborts the merge and raises.
  - `checkout_remote!(project, name)` — fetch, checkout, `pull --ff-only` (never discards local commits; a diverged branch raises).
  - `push_current!(project)` — returns `:pushed` / `:up_to_date`; a rejected push is retried once after `pull --rebase`; never forces.
  - `merge_in_progress?(project)` (`MERGE_HEAD` probe) and `abort_merge!(project)`.

## GitHub (`app/services/github/`)

- `github/client.rb` — `Github::Client.new(project)`: a thin facade (`delegate`) over a reader and a writer sharing one `Runner`. It also keeps the `FAILED_*` constants (reviewer parsing lives in `Workflow#reviewer_list`). Callers use the facade; collaborators are injectable (`reader:`, `writer:`) for specs. It owns no logic of its own — and does **not** own PR lookup.
- `github/reader.rb` — `Github::Reader`, query-only: `pr_url_for_branch`, `find_pr_url` (delegates to `PrLocator`), `pr_info`, `pr_title`, `current_login`, `merged?`, `review_decision` (any assigned reviewer approving wins), `checks_failing?`, `workflow_run_state`.
- `github/review_decision.rb` — `Github::ReviewDecision.call(latest_reviews, reviewers)`: pure review-state selection; an approval wins over a change request.
- `github/workflow_run_state.rb` — `Github::WorkflowRunState.call(runs, since:)`: pure selection and mapping of the newest eligible Actions run.
- `github/pr_locator.rb` — `Github::PrLocator#call(branch_name:, jira_ticket:, output: nil)`: finds the PR the agent opened. Order: last PR URL for this repo printed in the agent output → `gh pr view <branch>` → open PR whose head branch contains the Jira key. Raises `Github::CommandError` if none. Read-only.
- `github/writer.rb` — `Github::Writer`, side effects only: `checkout_pr!`, `request_review!` (via `gh api`, no `-R`), `enable_auto_merge!`.
- `github/runner.rb` — `Github::Runner#run!(argv, scope_to_repo: true, repo:)`: appends `-R <repo>` (skipped for `gh api`, which has none), runs `Open3.capture3(*argv, chdir: local_directory)`, raises `Github::CommandError`.
- `github/command_error.rb` — `Github::CommandError < StandardError`.

**PR creation is done by the agent, not the app.** The implementation stage's prompt tells the agent to run `gh pr create` during its coding run; the app only *finds* the PR afterwards (`find_pr_url`). Do not add a `create_pr` to Writer/Client.

## Conventions

- **Never interpolate into a shell string.** Build an argv array and pass it with `chdir:` (`Open3.capture3(*argv, chdir: dir)`); never `cd X && ...`, backticks or `system("...#{x}")`. Untrusted text (ticket text, PR titles, branch names, reviewer logins) is an argv element, never part of a command string.
- **Raise your own `CommandError`.** Each service raises its own class (`Git::CommandError`, `Github::CommandError`) on non-zero exit, with the command and stderr in the message. Don't rescue inside these objects (except deliberate fallbacks like `PrLocator#url_for_head`); `StageExecutor` in `ai-worker-stage-pipeline` turns stage failures into a `failed` `StageRun`.
- Probes use `success?`/`run`, mutations use `run!`/`checkout!`. Run `git` only through `Git::Shell`, `gh` only through `Github::Runner`.

## Specs

- Always `RAILS_ENV=test bundle exec rspec spec/services/git spec/services/github`.
- `spec/services/git/shell_spec.rb`, `branch_service_spec.rb` — real temp git repos via `GitRepoHelper` (`spec/support/git_repo_helper.rb`: `build_git_fixture(root)` → `[origin, clone]`, `build_other_clone`, `commit_file`, `git`) under `Dir.mktmpdir`, removed in `after`; assert the clone path is inside `Dir.tmpdir` first.
- `spec/services/github/reader_spec.rb`, `writer_spec.rb`, `runner_spec.rb`, `pr_locator_spec.rb` — stub `Open3.capture3` (return `[out, err, instance_double(Process::Status, success?: ...)]`) and assert the exact argv plus `chdir:`; use an unsaved `Project.new(... repo_full_name: "acme/widgets")`.
- `pr_locator_spec.rb` — `instance_double(Github::Runner)`, stubbing `run!` per argv. `client_facade_spec.rb` — `instance_double(Github::Reader/Writer)` injected into the facade.
- Specs of other code stub `Github::Client` / `Git::*`; never call real `gh` or touch a real project clone.
