---
name: ai-worker-review
description: Pre-PR local review for ai-worker, covering subprocess safety, stage/enum invariants, and audit-log completeness. Use before opening a PR against this repo.
argument-hint: '[--base <ref>] [--staged | --working]'
---

# ai-worker-review

Reviews the diff against `main` (or `--staged` / `--working` if passed) using `git -C <repo> diff <args>` — never `cd <repo> && git diff`, for the same non-interactive-safety reason the app's own services avoid `cd &&` strings.

1. Get the diff: `git -C . diff main...HEAD` (or the requested range).
2. Load `assets/review-checklist.md` — the stable, rarely-changing review criteria for this app.
3. For each changed file, find its owning skill in the table below (first match wins) and re-read *that skill* fresh, rather than trusting this review's memory of the codebase. Skill descriptions list the exact files each one owns.

   | Changed path | Skill |
   | --- | --- |
   | `app/services/ai_cli/**`, `app/services/ci/**`, `stages/run_tooling.rb` | `ai-worker-agent-cli` |
   | `app/services/{git,github}/**` | `ai-worker-git-github` |
   | `app/services/brainstorm/**`, `brainstorm_job.rb` | `ai-worker-brainstorm` |
   | `app/services/bugsnag/**`, `bugsnag_sync*` | `ai-worker-bugsnag-triage` |
   | `app/services/jira/{agent_fetcher,fetch_prompt,ticket_*,fetch_error,sync_cycle_source}.rb`, `jira_sync*` | `ai-worker-jira-ticket-sync` |
   | other `app/services/jira/**` (worklog/time-log files), `time_log.rb` | `ai-worker-jira-worklogs` |
   | `app/services/slack/{mention_*,review_sync,review_cycle_source,review_candidate,review_importer}.rb` | `ai-worker-pr-review-workflows` |
   | `app/services/slack/{review_notifier,ping_*,review_message,notify_error}.rb` | `ai-worker-slack-review-pings` |
   | `app/services/prompts/**`, `prompt_template.rb` | `ai-worker-prompts` |
   | `app/services/scheduling/**`, `workflow_scheduler_job.rb` | `ai-worker-scheduling` |
   | `stage_executor.rb`, `app/services/stages/**` | `ai-worker-stage-pipeline` |
   | `app/models/**`, `db/**` | `ai-worker-domain` |
   | other `app/jobs/**`, `app/services/**` | `ai-worker-orchestration` |
   | `spec/**` | `ai-worker-testing` |

   Narrower skills (`ai-worker-ci-loop`, `ai-worker-runbooks`, `ai-worker-browser-tests`, `ai-worker-workflow-lifecycle`, `ai-worker-cli-selection`, `ai-worker-project-dashboard`, `ai-worker-stage-types`, `ai-worker-detached-agent-runs`, `ai-worker-ui`) apply when the diff touches the files their descriptions name. A diff that only extracts, splits or moves code also needs `ai-worker-refactoring`.
4. Apply the checklist to the diff. Output format: `<file>:<line> — <SEVERITY> — <message>`, then a summary line with BLOCKING/HIGH/MEDIUM/LOW counts.
5. Stop after reporting — this skill does not commit, push, or open a PR. Hand off to a `pr-create`-style skill for that, if one is available in this project.
