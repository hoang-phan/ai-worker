# Runbook

## Running Sidekiq

`config/sidekiq.yml` declares two queues: `default` and `stage_execution`.
In production, run `stage_execution` as its own process at concurrency 1,
separate from everything else:

```
bundle exec sidekiq -C config/sidekiq.yml -q default -c 5
bundle exec sidekiq -C config/sidekiq.yml -q stage_execution -c 1
```

Why: `WorkflowSchedulerJob` fires every 10 minutes (`config/schedule.yml`)
and always returns quickly — `StageExecutor` starts the agent CLI (`claude -p` or `agent -p --force`) detached
(`Process.spawn`, output redirected to a log file under `log/ai_runs/`)
and never waits on it, so a run than can take many minutes never ties up
the job past Sidekiq's job timeout (this app used to run it blocking via
`Open3.popen3`, which is exactly what got killed by that timeout — see
`docs/ARCHITECTURE.md`). Each tick walks every `implementing`/`reviewing`
workflow in `position` order, so one waiting on review never blocks the
rest. The `Workflow#processing` guard (with `ai_pid`/`ai_log_path`/
`ai_started_at`/`ai_log_offset`) marks in-flight runs, which are polled
with `Process.wait2(pid, Process::WNOHANG)` (never blocking). Parallel
runs are limited by:

- one running agent per `project.local_directory` (stages `git checkout`/
  `pull`/`merge` in the clone, so two runs there would corrupt each other);
- `MAX_CONCURRENT_AGENTS` (env, default 3) agents overall.

Keep `stage_execution` at concurrency 1: those checks aren't atomic, so
ticks must serialize. Parallelism comes from the detached agent processes.

## Reading `StageRun` history

Every stage execution attempt writes at least one `StageRun`, visible on a
workflow's show page (`/projects/:id/workflows/:id`). `action` tells you
what happened:

- `started` — a the agent CLI (`claude -p` or `agent -p --force`) run was kicked off in the background for this
  stage. Expect a follow-up `ran_implementation`/`requested_changes_fixed`
  (success) or `failed` on a later tick — polling ticks in between that
  find the run still going don't write a `StageRun` row, only a
  `Rails.logger` line per new line of the agent's output.
- `ran_implementation` — implementation stage's the agent CLI (`claude -p` or `agent -p --force`) run finished
  successfully, PR opened. `output` has the full agent log.
- `approved_closed` — pr_check saw an approval; workflow is now `done`.
- `pr_merged_closed` — pr_check saw the PR already merged; workflow is now `merged`.
- `pr_merged_detected` — an idle tick found a `done` workflow's PR merged; now `merged`.
- `jira_updated` — the agent moved the Jira ticket to UAT/Releaseable; workflow is now `jira_updated`.
- `uat_waiting` / `uat_testing` / `uat_tested` — only for projects with "Test tickets on UAT automatically" on, after the ticket went to UAT. The workflow waits `uat_test_delay_minutes` (`workflows.uat_test_at`), then a `uat_test` stage runs the agent with a headless Playwright MCP browser (`@playwright/mcp`, pinned in `StageExecutor::PLAYWRIGHT_MCP_PACKAGE`). The agent follows the ticket's "How to test" comment on the project's UAT URL, records video + trace (files under `tmp/uat_runs/<workflow id>/<run>/`), attaches them to the ticket via the Jira REST API (`JIRA_EMAIL` / `JIRA_ACCESS_TOKEN` from `.env`) and comments the result, ending with `UAT_RESULT: PASSED|FAILED|BLOCKED`. No result line = the stage fails and retries like any other. An errored UAT workflow resumes to `uat_testing`.
- `local_testing` — only for projects with "Test PRs locally before review" on. When implementation finishes, the workflow goes here instead of straight to `reviewing`: a `local_test` stage checks out the branch, starts the development server, tests the ticket in the same Playwright browser as the UAT test, may fix and push, comments on the PR and ends with `LOCAL_TEST_RESULT: PASSED|FAILED|BLOCKED` (`StageRun: local_test_completed`); then `reviewing`. The test only reports (no code changes). On FAILED the agent prints a `LOCAL_TEST_FEEDBACK_BEGIN`/`END` block, stored in `workflows.local_test_feedback`; the PR still goes to `reviewing` and the feedback waits there: requested changes may make it obsolete, so a failure alone never triggers a fix. When `pr_check` sees `CHANGES_REQUESTED` (or an `APPROVED` that is turned into one by failing checks or pending local feedback, `StageRun: local_test_failing`) it runs one fix run covering review comments, failing checks and the local findings that still apply (the agent skips obsolete ones). The run ends with `LOCAL_RETEST: YES|NO` (missing = YES); the workflow goes back to `local_testing` (`local_test_retest_scheduled`) when pending local feedback was fixed or the agent said YES, so a reviewer-driven flow change is tested too, and re-requests review. At most `StageExecutor::MAX_LOCAL_TEST_ROUNDS` (3) tests per workflow; then `local_test_rounds_exhausted` and the PR just goes to review. BLOCKED never triggers a fix round. Auto-merge is enabled only after PASSED. The local login is `LOCAL_USERNAME`/`LOCAL_PASSWORD` in the agent's environment; test data goes in a reusable `prepare_test_data.rb` under `tmp/local_test_runs/<workflow id>/<timestamp>/`.
- `merge_check_failed` — `gh` lookup failed on an idle tick; retried next idle tick.
- `conflict_resolution_started` / `conflicts_resolved` — pr_check launched / finished an agent run resolving merge conflicts.
- `requested_changes_fixed` — pr_check saw requested changes, ran a fix,
  re-requested review. Expect another one of these (or `approved_closed`)
  on a later tick. `output` has the full agent log.
- `no_action_pending` — pr_check ran but the PR has no decision yet
  (review not submitted). Normal, not an error.
- `failed` — something raised (`Git::CommandError`, `Github::CommandError`,
  `AiCli::CommandError` — including a the agent CLI (`claude -p` or `agent -p --force`) run that exited
  non-zero, ran longer than `StageExecutor::STALE_AFTER` (3 hours), or
  whose exit status could no longer be determined — or a missing prompt
  template). Check the `error` column. `workflow.processing?` is cleared
  either way, so the next tick will retry from scratch rather than being
  permanently stuck polling a dead run.

- `resumed` — logged when someone resumes an `errored` workflow.

## Unsticking a failed stage

A `failed` run is retried on the next tick, up to
`StageExecutor::MAX_CONSECUTIVE_FAILURES` (3) in a row; then the workflow moves
to `status: errored`. The scheduler only picks `implementing`/`reviewing`
workflows, so an errored one isn't retried and doesn't block workflows queued
behind it. Fix the
cause first (bad branch state in the local clone, `gh`/agent CLI auth
expired, etc.), then press **Resume** on the workflow page, or:

```ruby
w = Workflow.find(...)
w.update!(status: w.resume_status) # reviewing if a PR exists, else implementing
```

## Manually running a stage right now

Don't wait for the cron tick:

```ruby
workflow = Workflow.find(...)
StageExecutor.new(workflow, workflow.current_stage).call
```

If this starts a the agent CLI (`claude -p` or `agent -p --force`) run, this call returns immediately (it
doesn't wait for `claude` to finish) — call it again (or wait for the next
cron tick) to poll it.

## If a workflow needs to be abandoned

Set `status: :done` directly (`workflow.update!(status: :done)`) — the
scheduler only looks at `implementing`/`reviewing` workflows, so this
immediately stops it being picked up. If a the agent CLI (`claude -p` or `agent -p --force`) run is still going
in the background (`workflow.processing?`), kill it first
(`Process.kill("TERM", workflow.ai_pid)`) since abandoning the
workflow this way doesn't do that for you.

A project can set `test_instructions` (free text, `{TEST_INSTRUCTIONS}`) for anything that holds on every environment, and `uat_instructions` for what is UAT-only (e.g. GitHub Actions wrappers); the UAT prompt includes both, test instructions first. `uat_instructions` (free text) that is added to the UAT prompt as `{UAT_INSTRUCTIONS}`: how to log in, what test data to prepare, or "read the guide at <path>". Nothing is hard-wired per project; the agent reads whatever the text points at. `uat_test` runs are started with `--disallowedTools "Bash(gh workflow run:*)" "Bash(gh api:*)"` (`StageExecutor::UAT_DISALLOWED_TOOLS`), so the agent can only dispatch workflows through a wrapper the instructions name; other stage types are unaffected.

## Slack review pings (optional)

When a PR is waiting on reviewers (after implementation, after a passed/finished local test, and after review-fix pushes) the app can post one line to a Slack channel, e.g. `:eyes: <@U1> <@U2> please review <pr|ENG-1 Fix thing>` (after fixes: a reply in the same thread tagging the reviewers, listing what was fixed, and asking them to re-review). The first message's `ts` is saved on the workflow (`slack_review_thread_ts`); paste a Slack message link into the workflow's edit form to use an existing thread instead. A re-request with no saved thread starts one. The post is made by a short detached agent run (`SLACK_PING_MODEL`, default `haiku`; only `slack_send_message` allowed) through the Slack MCP connector, so it comes from your Slack user, not an app; no bot token is needed. The run prints the message permalink and `SlackPingJob` (every minute) saves it as the thread, so a re-request that fires before then starts a new thread. Set, per project, the channel ID and the `github-login=SlackUserID` map. Unmapped reviewers are named in plain text. Failures are logged as `slack_review_notify_failed` stage runs and never fail the stage.
