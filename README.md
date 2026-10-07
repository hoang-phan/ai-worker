# AI Worker

Automates the "implement → open PR → address review → merge" loop across
multiple local projects using an AI coding agent CLI (`claude` or Cursor's `agent`) and `gh`.

You define a **Project** (a local git clone) and one or more **Workflows**
on it (a Jira ticket, a branch, a GitHub reviewer, which AI agent to use, and which
skills to use). Every 30 minutes a Sidekiq cron job picks the first active
workflow and runs its next stage:

1. **implementation** — creates the branch, runs the agent (`claude -p` / `agent -p --force`) with a
   rendered implementation prompt (which itself opens the PR), and records
   the PR URL.
2. **pr_check** — checks the PR's review decision via `gh`. Approved closes
   the workflow. Changes requested re-runs the agent against a review-fix
   prompt and re-requests review. Anything else is a no-op. This stage
   repeats every tick until the workflow closes.

See `docs/ARCHITECTURE.md` for the full design, `docs/ADDING_A_PROJECT.md`
before registering a new project, `docs/PROMPT_TEMPLATES.md` for the
placeholder reference, and `docs/RUNBOOK.md` for day-to-day operation.

## Setup

- Ruby (see `.ruby-version`), Rails 8.1, SQLite.
- Redis, reachable at `REDIS_URL` (defaults to `redis://localhost:6379/0`).
- `gh` CLI, authenticated (`gh auth login`) with access to every project's repo.
- `claude` CLI and/or Cursor's `agent` CLI, authenticated, on `PATH` (whichever agents your workflows select).

```
bundle install
bin/rails db:migrate
bin/rails server -b 0.0.0.0 # the CRUD UI, at http://localhost:3000
bundle exec sidekiq -C config/sidekiq.yml   # the scheduler + stage runner
```

In production, run a second Sidekiq process dedicated to the
`stage_execution` queue at concurrency 1 (see `docs/RUNBOOK.md`) — each job
on it tracks an agent run that can take minutes.
