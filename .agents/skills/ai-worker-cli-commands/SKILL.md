---
name: ai-worker-cli-commands
description: Owns ai-worker agent command builders. Use for app/services/ai_cli/command.rb, app/services/ai_cli/command/{claude,codex,cursor}.rb, spec/services/ai_cli/command_spec.rb, or spec/services/ai_cli/command/{claude,codex,cursor}_spec.rb.
---

# ai-worker CLI commands

Owns the pure argv builders for non-interactive Claude, Codex, and Cursor runs. Process spawning and polling belong to `ai-worker-agent-cli`; provider selection, settings, rotation, and adapters belong to `ai-worker-cli-selection`; browser-test setup and `CursorMcpFile` belong to `ai-worker-browser-tests`.

## File map

- `app/services/ai_cli/command.rb` — `AiCli::Command` dispatches an agent to its provider builder, raises `AiCli::CommandError` for an unknown agent, and reads Claude-format `mcpServers` JSON through `.mcp_servers`.
- `app/services/ai_cli/command/claude.rb` — `AiCli::Command::Claude` builds Claude argv.
- `app/services/ai_cli/command/codex.rb` — `AiCli::Command::Codex` builds `codex exec` argv and translates MCP server JSON into Codex TOML overrides.
- `app/services/ai_cli/command/cursor.rb` — `AiCli::Command::Cursor` chooses the Cursor executable and builds Cursor argv.
- `spec/services/ai_cli/command_spec.rb` — dispatch-level argv coverage for all agents.
- `spec/services/ai_cli/command/claude_spec.rb` — Claude argv and flag-order coverage.
- `spec/services/ai_cli/command/codex_spec.rb` — Codex model/effort and MCP TOML conversion coverage.
- `spec/services/ai_cli/command/cursor_spec.rb` — executable selection and help-probed flag coverage.

## Builder contracts

- Keep argv as arrays. The builders do not spawn a process or interpolate a shell command.
- `Command` accepts the common `prompt`, tool lists, MCP config, model, effort, verbose, executable-check, and help-probe inputs, then delegates to the selected provider builder. Agent-specific builders deliberately ignore unsupported inputs.
- Keep external lookup seams injectable: `executable_check:` and `help_probe:` reach Cursor through `Command`; `mcp_servers:` reaches Codex. Their real defaults may inspect PATH, run `<binary> --help`, or read JSON, but specs pass lambdas so they never invoke installed CLIs.

### Claude

Claude supports tool lists, model, and effort. Its argv order is: `claude -p <prompt>`, permission choice, MCP config, disallowed tools, model, effort, then verbose stream-json flags. An `allowed_tools` list emits `--allowedTools <tools...>`; otherwise it emits `--dangerously-skip-permissions`. When present, append `--mcp-config <path>`, `--disallowedTools <tools...>`, `--model <model>`, and `--effort <effort>` in that order. Verbose Claude ends with `--output-format stream-json --verbose --include-partial-messages`.

### Codex

Codex supports model, effort, and MCP overrides; it does not receive Claude tool-list or verbose flags. Its argv is `codex exec`, followed by MCP `-c` overrides, then the effort override, `--dangerously-bypass-approvals-and-sandbox`, optional `--model <model>`, and the prompt.

`Command.mcp_servers` reads a Claude-format JSON file's `mcpServers` object. For each server, Codex emits paired `-c` TOML assignments in source hash order: required `command`, fixed `startup_timeout_sec=90`, optional `args` as a JSON array (including an explicit empty array), and optional nonblank `env` as a TOML inline table. Quote scalar values with JSON encoding; render inline-table keys and values with JSON quoting. Model reasoning effort is `-c model_reasoning_effort=<JSON-quoted effort>`. MCP overrides must stay after `exec` and before execution flags.

### Cursor

Cursor owns executable and help probing. Prefer `agent` when present on PATH, otherwise `cursor-agent`, and fall back to `agent` if neither check succeeds. Its argv is `<resolved binary> -p <prompt> --force`. With an MCP config, append `--approve-mcps` only when the resolved binary's `--help` output advertises that flag. `DEFAULT_EXECUTABLE_CHECK` and `DEFAULT_HELP_PROBE` remain the production seams.

## Verification

Run the focused command-builder suite after these changes:

`RAILS_ENV=test bundle exec rspec spec/services/ai_cli/command_spec.rb spec/services/ai_cli/command`

Do not invoke real Claude, Codex, or Cursor binaries in these specs; use the injectable seams and temporary MCP JSON files.
