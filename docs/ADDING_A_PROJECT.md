# Adding a project

## Requirements

A project must, on the machine running the Sidekiq `stage_execution`
worker:

1. Have an existing local clone at some absolute path, checked out with a
   `main` branch and an `origin` remote reachable by `git fetch`.
2. Have `gh` already authenticated (`gh auth login`) with access to its
   GitHub repo.
3. Have the agent CLI (`claude` or `agent`) on `PATH`, already authenticated.

Register it via the UI (`/projects/new`): `name`, `local_directory` (the
absolute path from #1), `repo_full_name` (`org/repo`, used for `gh -R`).

## Self-evolving: registering ai-worker as its own project

Never register the checkout ai-worker is running from. Agents `checkout`,
`pull`, `merge` and may run migrations in the project's clone; in the live
checkout that swaps the running code and trips `PendingMigrationError` or
touches the real dev DB. `Project` validation and `StageExecutor` both reject
a `local_directory` that resolves (via `realpath`) to `Rails.root`.

1. Make a sibling clone: `git clone git@github.com:hoang-phan/ai-worker.git ~/code/ai-worker-self`
   and run `bundle install` there. SQLite lives in `storage/` (gitignored),
   so the clone has its own databases — migrations there can't touch real data.
2. Register it with `local_directory` = the clone, kind `personal` (each workflow is one task committed in the
   clone, no PR) and `repo_full_name` = `hoang-phan/ai-worker`. Give its stage a dedicated prompt template that says:
   work only in the clone, use `RAILS_ENV=test`, never run migrations or write to any DB other than the clone's own,
   and push the commit to `origin main` (no force-push).
3. Promotion is manual. After a task finishes and is pushed, in the live checkout: back up
   `storage/development.sqlite3`, `git pull origin main`, `bin/rails db:migrate`, restart Sidekiq.
   The agent never does this.

## Give the project its own narrowly-scoped skills

The `{SKILLS}` placeholder (see `docs/PROMPT_TEMPLATES.md`) is only useful
if the target project actually has Claude Code skills to point at. Without
one, an unattended `claude -p` implementation run has to read the whole
repo to figure out where to make a change — slow, and prone to touching
things outside the ticket's scope.

The pattern to copy is `final-five`'s `.claude/skills/ff-candidate-app/SKILL.md`:

- The skill's frontmatter `description` states its scope as a trigger
  clause: *"Use for any task touching `<paths>`."*
- The body opens with an authoritative file map of **only** that package/
  area — not the whole repo.
- It narrows a more general project-wide skill's discipline (there,
  `ff-dev`) down to just the conventions that area cares about.

Concretely, when onboarding a project:

1. Identify the natural seams in it (a package, a Rails engine, a feature
   directory, a set of routes) — the same boundaries you'd use to decide
   "does this ticket touch area X."
2. For each seam that's a plausible unattended-implementation target,
   write a `.claude/skills/<area>/SKILL.md` in *that project's own repo*
   (not in `ai-worker`) with a scoping `description` and a file map,
   following the `ff-candidate-app` example above.
3. When creating a Workflow, put the matching skill name(s) into its
   `skills` field. The implementation and pr_check prompt templates
   should both instruct Claude to use them (see the example templates in
   `docs/PROMPT_TEMPLATES.md`) — that's what keeps an unattended run from
   reading the whole target codebase.

This repo's own `.claude/skills/` (`ai-worker-domain`,
`ai-worker-orchestration`, `ai-worker-ui`, `ai-worker-review`)
follow the identical pattern, scoped to `ai-worker`'s own subsystems —
use them as a second worked example.
