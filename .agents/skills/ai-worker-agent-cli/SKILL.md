---
name: ai-worker-agent-cli
description: Applies ai-worker's agent-run process, polling, logs, verdict, detached-run, CI-command, and run-tooling discipline. Use for app/services/ai_cli/{runner,process_status,run_poller,stale_run,log_tail,run_verdict,run_logs,output,detached_run,command_error}.rb, app/services/ci/**, app/services/stages/run_tooling.rb, or their mirrored specs; command builders use ai-worker-cli-commands.
---

# ai-worker agent CLI layer

Command builders and argv flags are specialised in `ai-worker-cli-commands`. Browser-test CLI setup, credentials, and MCP delivery are specialised in `ai-worker-browser-tests`.

Every background run the app starts — the agent CLI (claude, cursor `agent`, codex) and the `ci_check` command — is launched and polled by these objects. Runs are detached: a job starts one, records its pid/log state on the workflow (or in a sync's `tmp/` dir) and a later scheduler tick polls it. Read the file before changing it; this is a map, not a substitute.

Scope: agent-run process lifecycle files `app/services/ai_cli/{runner,process_status,run_poller,stale_run,log_tail,run_verdict,run_logs,output,detached_run,command_error}.rb`, `app/services/ci/**`, `app/services/stages/run_tooling.rb`, and their mirrored specs. For `app/services/ai_cli/command.rb`, `app/services/ai_cli/command/{claude,codex,cursor}.rb`, and their mirrored specs, use `ai-worker-cli-commands`. The stage executor and services that launch, finish, and rescue these runs: `ai-worker-stage-pipeline`; adding a stage type: `ai-worker-stage-types`. The detached sync services built on `DetachedRun`: `ai-worker-detached-agent-runs`. Prompt text: `ai-worker-prompts`. Scheduler capacity rules: `ai-worker-scheduling`.

## File map (the whole scope)

**Launching**
- `ai_cli/runner.rb` — `AiCli::Runner`, the single place that launches the agent CLI. Not blocking.
  - `Runner.start(project_directory, prompt, log_path:, allowed_tools: nil, mcp_config: nil, env: {}, disallowed_tools: [], model: nil, effort: nil, provider: nil)` (class and instance) builds the argv with `Command`, then calls `Providers.fetch(agent).wrap(...)` (which handles provider-specific wrapping, including Cursor MCP setup) before `Process.spawn` with `chdir:`, stdin `File::NULL`, stdout/stderr appended to `log_path`; returns the pid. The spawn env unsets `LEAKED_ENV` (Bundler/Ruby/Rails vars of this app), sets `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` and merges `env` (values `to_s`).
  - `Runner.poll(pid)` → `:running` or `[:completed, Process::Status-or-nil]` (delegates to `ProcessStatus`).
  - `Runner.agent` (read by `RunPoller` and `#agent_command`) returns `AgentSetting.current`; change the setting through `AgentSetting`. `provider:` on `start` names the agent CLI for that run (the app-wide setting when nil).
  - Pass per-run command options through unchanged; their agent-specific flags and MCP behavior are owned by `ai-worker-cli-commands`. `env` is extra variables for the agent process.
- CLI settings, rotation, providers, and `RunProvider`: see `ai-worker-cli-selection`.
- Command-builder files are owned by `ai-worker-cli-commands`; see that skill for file maps, argv order, capability flags, MCP conversion, seams, and focused specs.
- `ai_cli/cursor_mcp_file.rb` — `AiCli::CursorMcpFile.new(project_directory, mcp_config).wrap(cmd)`: writes the run's servers to `<cwd>/.cursor/mcp.json` (an existing file is kept as `.ai-worker-bak`), excludes it in `.git/info/exclude`, and returns `cmd` wrapped in an `sh -c` trap that restores the original file when the run ends.
- `ai_cli/browser_test_run.rb` — Browser-test setup and its spec recipe: see `ai-worker-browser-tests`.
- `ci/command_runner.rb` — `Ci::CommandRunner.start(project_directory, command, log_path:, env: {}, **)`: same signature as `Runner.start` so `Stages::AiRunLauncher` launches either. Runs the project's `ci_command` (a trusted project setting) as `bash -lc <command>` in its own process group (`pgroup: true`), same log redirection and `LEAKED_ENV` unsetting.
- `stages/run_tooling.rb` — `Stages::RunTooling.for(stage)` → a `Tooling(runner:, poller_class:)` value: `PLAIN_COMMAND` (`Ci::CommandRunner` + `Ci::CheckPoller`) for `ci_check?` stages, else `AGENT_CLI` (`AiCli::Runner` + `AiCli::RunPoller`). `StageExecutor` takes it as `tooling:`.

**Polling and results**
- `ai_cli/process_status.rb` — `AiCli::ProcessStatus.new(process: Process).call(pid)`: `wait2(WNOHANG)`; on `ECHILD` (child of a restarted Sidekiq) falls back to `getpgid` liveness, and `ESRCH` means `[:completed, nil]`.
- `ai_cli/run_poller.rb` — `AiCli::RunPoller.new(pid:, log_path:, log_offset:, started_at:, log_tag:, stale_after:, runner: AiCli::Runner, kill: Process.method(:kill))`; `call` → `:running` or `[:finished, output]`, raising `AiCli::CommandError` on failure or timeout. Only a run still alive can be stale (kills it with `TERM`); `log_offset` is exposed for the caller to persist.
- `ai_cli/stale_run.rb` — `AiCli::StaleRun`: shared stale-run decision used by `RunPoller` and `Ci::CheckPoller` (`spec/services/ai_cli/stale_run_spec.rb`).
- `ai_cli/log_tail.rb` — `AiCli::LogTail.new(log_path:, log_tag:)`: `read_from(offset)` → `[content, new_offset]`, mirroring each new line into `Rails.logger` as `[ai_cli <tag>] ...`; `full` returns the whole log or `""`. `RunPoller` owns one.
- `ai_cli/run_verdict.rb` — `AiCli::RunVerdict.new(exit_status:, output:, agent:, pid:).verify!` (pure, no I/O): returns the output or raises `AiCli::CommandError`. A nil status (reaped elsewhere) is judged from the final claude result event; no result event means failed.
- `ai_cli/run_logs.rb` — `AiCli::RunLogs.new_path(workflow_id, at:, dir:)` (`log/ai_runs/workflow-<id>-<unix>.log`) and `latest(workflow_id, dir:)` (newest by mtime; the `-` after the id keeps workflow 1 apart from 12).
- `ai_cli/output.rb` — `AiCli::Output.new(text)`, pure: `variables` (`VAR:` / `VAR_BEGIN`..`VAR_END`), `jira_result`, `uat_result`, `local_test_result`, `ci_verdict`, `retest_requested?` (missing counts as YES), `local_test_feedback_block`, `fixed_summary`, `lessons`, `follow_ups` (rows cleaned by `Workflows::ProposalNormalizer`), `posted?`, `result_event` (last valid claude result event), `final_outcome` (`:success` / `:error` / nil from it). Last match wins. Adding a marker: `ai-worker-stage-types`.
- `ci/check_poller.rb` — `Ci::CheckPoller.new(pid:, log_offset:, started_at:, stale_after:, runner:, kill:, **)` (extra keywords from the executor are ignored); `call` → `:running` or `[:finished, exit_code]`. A non-zero exit is a normal result (the verify stage reads the failure); only a timeout (kills the process group `-pid`) or an unknown status raises `AiCli::CommandError`.
- `ai_cli/detached_run.rb` — `AiCli::DetachedRun.new(dir:, result_name:, stale_after:, error_class:, runner: AiCli::Runner)`: the pid/started_at/`agent.log`/result-file state machine for the sync services (`start`, `running?`, `poll`, `read_rows`, `last_started_at`, `log_path`, `result_path`). Its contract and checklist: `ai-worker-detached-agent-runs`.
- `ai_cli/command_error.rb` — `AiCli::CommandError < StandardError`; the sibling classes are `Git::CommandError` and `Github::CommandError` (one per service).

## Conventions

- **Detached, never blocking.** Starting a run returns a pid at once; a job never waits on the agent (a run can outlast Sidekiq's job timeout). Everything that starts a run must record the state a later tick needs (pid, log path, start time, log offset, or the sync's `tmp/` files); everything that finishes one must clear it. Polling is `Runner.poll` / `ProcessStatus` with `WNOHANG`, never `wait`.
- **`Process.spawn` with an argument array.** Never build `cd X && ...` strings; pass argv plus `chdir:`. Untrusted text (ticket, Slack, PR text) goes into the prompt argument or env, never into a shell string. The only shell string is `Ci::CommandRunner`'s `bash -lc <project.ci_command>`, a trusted project setting — don't feed it anything else — and `CursorMcpFile`'s fixed restore script (the command is passed as `"$@"` arguments).
- **Secrets only as env vars.** UAT/local logins reach the agent as environment variables of the spawned process (`BrowserTestRun#env` → `Runner.start(env:)`), never in prompts or logs. Jira, Slack and Bugsnag go through the agent's own MCP connectors, so the app holds no tokens for them.
- **Least tool access.** Give a run the narrowest tools that work: `allowed_tools` allowlists for the Slack, Bugsnag and brainstorm runs (claude; headless mode can't ask, so unlisted tools are denied), `disallowed_tools` such as `gh workflow run` / `gh api` for UAT/local tests (deny rules beat `--dangerously-skip-permissions`), the review ping gets only the Slack send-message tool. Other agents lack these flags, so also say it in the prompt.
- **Raise `AiCli::CommandError`, don't rescue it here.** Runners/pollers raise on failure or timeout; `StageExecutor` in `ai-worker-stage-pipeline` turns stage failures into a `failed` `StageRun`, and the sync jobs rescue their own `FetchError` / `AiCli::CommandError`.
- **Keep the seams injectable.** Collaborators are keyword arguments with real defaults so specs pass doubles: `runner:` (`RunPoller`, `CheckPoller`, `DetachedRun`), `kill:` (pollers), `process:` (`ProcessStatus`), `root:` (`BrowserTestRun`), and `dir:` / `at:` (`RunLogs`). A new launcher keeps `start`'s signature identical to `AiCli::Runner.start` so `AiRunLauncher` can use it. Pure decisions (`RunVerdict`, `Output`) stay free of I/O. Command-builder seams are documented in `ai-worker-cli-commands`.

## Specs

- Always `RAILS_ENV=test bundle exec rspec spec/services/ai_cli spec/services/ci spec/services/stages/run_tooling_spec.rb`; command-builder changes also run the focused command suite in `ai-worker-cli-commands`.
- `spec/services/ai_cli/`: `runner_spec.rb` (agent setting delegation, `#start` spawn args/env), `agent_setting_spec.rb`, `cursor_mcp_file_spec.rb`, `browser_test_run_spec.rb` (`root:` temp dir), `run_poller_spec.rb` (`runner` and `kill` doubles, temp log dir), `stale_run_spec.rb`, `run_verdict_spec.rb`, `log_tail_spec.rb`, `run_logs_spec.rb`, `process_status_spec.rb` (fake `process:`), `output_spec.rb` (every marker incl. missing and last-match-wins), `detached_run_spec.rb` (the model for fake-`runner:` specs). Command specs are listed in `ai-worker-cli-commands`.
- `spec/services/ci/`: `command_runner_spec.rb`, `check_poller_spec.rb` (`runner` and `kill` doubles). `spec/services/stages/run_tooling_spec.rb`: which tooling `for(stage)` picks.
- Use `TmpDirHelper`'s `let_tmpdir` / `make_tmpdir` for log/state/clone dirs. Stub `Process.spawn` or inject doubles — never start a real `claude`/`agent`/`codex` or run a real CI command.
