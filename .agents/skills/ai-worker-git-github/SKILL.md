---
name: ai-worker-git-github
description: Applies ai-worker's Git layer discipline. Use for any task touching app/services/git/** or matching specs (spec/services/git/**) — Git::Shell, BranchService, Pusher, MergeState, and Git::CommandError.
---

# ai-worker Git layer

Git subprocesses run inside the project's clone (`project.local_directory`). Read the file before changing it; this is a map, not a substitute. GitHub service ownership is in `ai-worker-github`.

## Git (`app/services/git/`)

- `git/shell.rb` — `Git::Shell.new(directory)`; the only place `git` is spawned.
  - `run(argv)` → `[out, err, status]` via `Open3.capture3(*argv, chdir: directory)`; never raises.
  - `run!(argv)` → stdout, or raises `Git::CommandError` (`"<cmd> failed: <stderr or stdout>"`).
  - `success?(argv)` → boolean from the exit status (probes like `rev-parse --verify`).
  - `checkout!(argv)` → a `git checkout` that, only when stderr matches `would be overwritten by checkout`, runs `git stash push --include-untracked -m "ai-worker: auto-stash ..."` and retries once. Nothing is discarded. Any other failure raises.
- `git/command_error.rb` — `Git::CommandError < StandardError`.
- `git/pusher.rb` — `Git::Pusher.new(project, shell:)#push_current!` (and private `ahead_count`): returns `:pushed` / `:up_to_date`; a rejected push is retried once after `pull --rebase`; never forces.
- `git/merge_state.rb` — `Git::MergeState.new(project, shell:)`: `merge_in_progress?` (`MERGE_HEAD` probe), `abort_merge!`, `merge_main!` (`:merged` / `:conflict`, conflicted-files probe; any other failure aborts the merge and raises `Git::CommandError`).
- `git/branch_service.rb` — `Git::BranchService`, built on a `Shell` (and a `MergeState` for `update_with_main!`); class methods wrap instance methods, with `push_current!`, `merge_in_progress?` and `abort_merge!` as one-line forwarders to `Pusher` / `MergeState`:
  - `create_branch!(project, name)` — checkout + pull `main`, then checkout the branch (create with `-b` if absent locally).
  - `update_with_main!(project, name)` — review-fix flow: same, branch from `origin/<name>` if not local, then merge `main`; returns `:merged` or `:conflict` (conflicted merge left in place for the agent). Any other merge failure aborts the merge and raises.
  - `checkout_remote!(project, name)` — fetch, checkout, `pull --ff-only` (never discards local commits; a diverged branch raises).
  - `push_current!(project)` — returns `:pushed` / `:up_to_date`; a rejected push is retried once after `pull --rebase`; never forces.
  - `merge_in_progress?(project)` (`MERGE_HEAD` probe) and `abort_merge!(project)`.

## Conventions

- **Never interpolate into a shell string.** Build an argv array and pass it with `chdir:` (`Open3.capture3(*argv, chdir: dir)`); never `cd X && ...`, backticks or `system("...#{x}")`. Untrusted text (ticket text, PR titles, branch names, reviewer logins) is an argv element, never part of a command string.
- **Raise `Git::CommandError`.** Git commands report a non-zero exit with the command and stderr in the message. Don't rescue inside these objects; `StageExecutor` in `ai-worker-stage-pipeline` turns stage failures into a `failed` `StageRun`.
- Probes use `success?`/`run`, mutations use `run!`/`checkout!`. Run `git` only through `Git::Shell`.

## Specs

- `spec/services/git/shell_spec.rb`, `branch_service_spec.rb`, `pusher_spec.rb`, `merge_state_spec.rb` — real temp git repos via `GitRepoHelper` (`spec/support/git_repo_helper.rb`: `build_git_fixture(root)` → `[origin, clone]`, `build_other_clone`, `commit_file`, `git`) under `let_tmpdir(:root, ...)`; assert the clone path is inside `Dir.tmpdir` first. `branch_service_spec.rb` keeps orchestration plus one forwarding example per class method; push and merge-state behaviour is covered in `pusher_spec.rb` / `merge_state_spec.rb`.
- Specs of other code stub `Git::*`; never touch a real project clone except the temp repos above.
