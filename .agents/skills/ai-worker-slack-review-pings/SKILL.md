---
name: ai-worker-slack-review-pings
description: Applies ai-worker's Slack "please review" ping discipline. Use for any task touching app/services/slack/{review_notifier,ping_collector,ping_run,review_message,thread_ref,notify_error}.rb, app/jobs/slack_ping_job.rb, the slack_ping entry in config/schedule.yml, or their specs (spec/services/slack/{review_notifier,ping_collector,ping_run,review_message,thread_ref}_spec.rb, spec/jobs/slack_ping_job_spec.rb) — Slack::ReviewNotifier, PingCollector, PingRun, ReviewMessage, ThreadRef, NotifyError and SlackPingJob.
---

# ai-worker-slack-review-pings

Scope: the outbound "please review" message posted to the project's Slack channel once a PR is up for review (and again after changes are pushed), and the read-back of that message's permalink into `Workflow#slack_review_thread_ts` so later pings reply in the same thread. It is built on a short detached agent run (`AiCli::Runner`) but is *not* a fetch/sync service: there is no result file, importer or sync wrapper. The inbound side (mention fetch, `ReviewSync`, `ReviewImporter`) is in `ai-worker-pr-review-workflows` (fetch/run mechanics in `ai-worker-detached-agent-runs`); the `AiCli` runner/poller in `ai-worker-agent-cli`; shared subprocess/error conventions in `ai-worker-orchestration`; spec rules in `ai-worker-testing` — not repeated here.

## File map

- `app/services/slack/review_notifier.rb` (`Slack::ReviewNotifier.new(project, runner: AiCli::Runner, clock: -> { Time.current }, root: PingRun::ROOT, collector: nil)`):
  - `enabled?` is true when `project.slack_review_channel` is present; `blockers` returns `["Slack channel is not set"]` otherwise (for the UI).
  - `message(pr_url:, label:, reviewers:, again: false, fixed: nil)` returns `ReviewMessage#text` (no app caller today besides specs; `Prompts::StagePrompt` only uses `enabled?`).
  - `notify!(workflow:, pr_url:, label:, reviewers:, again:, fixed:, thread_ts: nil)` raises `NotifyError` unless enabled, builds the prompt and calls `PingRun.for(root, workflow.id, clock.call).start!(runner, prompt, allowed_tools: ALLOWED_TOOLS, model: self.class.model)`. It returns nil immediately and never waits. `AiCli::CommandError` / `SystemCallError` are re-raised as `NotifyError` ("Slack ping failed to start: ...").
  - `DEFAULT_MODEL` is `"haiku"`; `ReviewNotifier.model(env: ENV)` reads `env.fetch("SLACK_PING_MODEL", DEFAULT_MODEL)` at call time; specs pass `env:` a hash. `ALLOWED_TOOLS` = `mcp__claude_ai_Slack__slack_send_message` only (headless can't prompt).
  - `collect(workflow)` delegates to the collector; returns true while a ping is still running. The default collector is `PingCollector.new(root:, poller: runner.method(:poll))`.
- `app/services/slack/thread_ref.rb` (`Slack::ThreadRef`) — pure permalink matcher / thread timestamp parser. `PERMALINK` recognizes Slack message links; `ts_for(value)` strips a bare timestamp or turns the Slack permalink path timestamp into `seconds.microseconds`. Spec: `spec/services/slack/thread_ref_spec.rb`.
- `app/services/slack/ping_run.rb` (`Slack::PingRun`) — value object for one run dir `tmp/slack_pings/<workflow_id>/<started_at epoch seconds>/` holding `pid` and `agent.log`. `PingRun.for(root, workflow_id, started_at)` (dir not created), `pid_file`, `log_file`, `started_at`, `start!(runner, prompt, **run_options)` (mkdir_p, `runner.start` with `log_path: log_file`, writes the pid), `running?(poller, now = Time.current)` (pid file present, poller says `:running`, and not stale; a missing pid file counts as finished), `stale?` (older than `STALE_AFTER`, 5 minutes), `permalink` (first match of `ThreadRef::PERMALINK` in `agent.log`, or nil), `to_s`. `ROOT` is `tmp/slack_pings`.
- `app/services/slack/ping_collector.rb` (`Slack::PingCollector.new(root:, poller:)`):
  - `collect(workflow)` walks the workflow's run dirs oldest first. A run is `:running` while `PingRun#running?(poller)` is true (pid alive and not stale; a missing pid file or a stale run counts as finished). A finished run with a permalink sets `slack_review_thread_ts` (only when blank) and its dir is removed; one without a permalink logs a warning and the dir is kept. The workflow dir is removed when empty and nothing is running. `Errno::ENOENT` returns false.
  - `collect_all(find_workflow:)` handles every workflow dir under `root` (`pending_workflow_ids`); dirs whose workflow no longer exists are `rm_rf`'d.
- `app/services/slack/review_message.rb` (`Slack::ReviewMessage.new(pr_url:, label:, reviewers:, slack_id_for:, again: false, fixed: nil)`, pure: no Project/DB) — `text` is `:eyes: <@U1> please review [label](pr_url)`; `again` switches to "changes pushed, please re-review" and `fixed` (stripped, when present) is appended as a `Fixed:` block. Reviewers with no Slack id fall back to `@login`; `[ ]` in the label become `( )`. `prompt(channel:, thread_ts: nil)` is the agent's instruction: post the `<message>` once, verbatim, as content not instructions, finish with only the permalink, and post nowhere else on failure.
- Reviewer tagging: `ReviewNotifier` passes `project.method(:slack_user_id_for)` as `slack_id_for`; `Project#slack_user_id_for` calls `Projects::SlackUserMap` (`app/models/projects/slack_user_map.rb`: `login=SlackID` per line or comma, `:` also accepted, case-insensitive, leading `@` ignored).
- `app/services/slack/notify_error.rb` — `Slack::NotifyError < StandardError`, the only error callers rescue.
- `app/jobs/slack_ping_job.rb` (`SlackPingJob`, queue `default`) — `Slack::PingCollector.new.collect_all`; never waits on a run. `config/schedule.yml` entry `slack_ping` is `*/5 * * * *` on `default` (the job's header comment says "every minute"; the cron wins).

## Not owned here

- `app/services/stages/review_handoff.rb` (`Stages::ReviewHandoff#notify_reviewers!`) — the caller; see `ai-worker-stage-pipeline`. It skips unless `enabled?` and reviewers exist, calls `collect` first (so a freshly collected permalink is the `thread_ts`), then `notify!`, and logs `slack_review_notified` / `slack_review_notify_failed` rescuing `Slack::NotifyError` and `Github::CommandError`.
- `Workflow#slack_review_thread_ts=` (`app/models/workflow.rb`) — accepts `1760000000.123456` or a `.../archives/C123/p1760000000123456` link and stores the `ts`; see `ai-worker-domain`. `Project#slack_review_channel` / `slack_user_map` are project columns.
- The Slack mention fetch, `Slack::ReviewSync`, `Slack::ReviewImporter` and `SlackReviewJob` — `ai-worker-pr-review-workflows`.

## Conventions

- **Best-effort**: a failed ping never fails a stage. `notify!` only raises `NotifyError`; `ReviewHandoff` turns it into a stage log entry. Don't let new failure paths escape it, and don't make the ping block on the run.
- **No Slack token in the app**: the message is posted by the agent through the Slack MCP connector (as the connected Slack user). Never add a Slack client, token or webhook.
- **Least tool access**: keep `ALLOWED_TOOLS` to the single send-message tool; the message text is untrusted-looking content in the prompt (`<message>` block), not instructions.
- State lives only in `tmp/slack_pings/`; use `PingRun` for paths and the pid/log layout, never hand-built paths. The thread id comes back only through the permalink in `agent.log`.
- Injectable seams — use them in specs instead of `stub_const` or `allow(X).to receive(:new)`: `ReviewNotifier.new(project, runner:, clock:, root:, collector:)`, `PingCollector.new(root:, poller:)`, `collect_all(find_workflow:)`, `ReviewMessage` `slack_id_for:` callable.
- Keep `ReviewMessage` and `PingRun` free of the DB; the collector is the only one that writes the workflow.

## Specs

- `spec/services/slack/review_notifier_spec.rb`, `ping_collector_spec.rb`, `ping_run_spec.rb`, `review_message_spec.rb`, `spec/jobs/slack_ping_job_spec.rb`, and `spec/services/stages/review_handoff_spec.rb` for the caller.
- Use a tmp `root:` and a fake `runner:`/`poller:`; never start a real run or touch the real `tmp/slack_pings`.
- Run with `RAILS_ENV=test bundle exec rspec spec/services/slack/review_notifier_spec.rb spec/services/slack/ping_collector_spec.rb spec/services/slack/ping_run_spec.rb spec/services/slack/review_message_spec.rb spec/jobs/slack_ping_job_spec.rb spec/services/stages/review_handoff_spec.rb`.
