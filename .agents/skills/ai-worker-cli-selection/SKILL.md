---
name: ai-worker-cli-selection
description: Selects the agent CLI and provider for a run — rotation (AiCli::Rotation, Workflow#rotation_provider!), the app-wide AgentSetting fallback and the AiCli::Providers registry, resolved by Stages::RunProvider. Use for app/services/stages/run_provider.rb; app/services/ai_cli/{rotation,providers,provider,agent_setting}.rb; app/services/ai_cli/provider/{claude,codex,cursor}.rb; app/controllers/{settings_controller,settings/rotations_controller}.rb; app/controllers/concerns/settings_screen.rb; app/views/settings/show.html.erb; and their listed specs, including spec/services/ai_cli/provider/{claude,codex,cursor}_spec.rb.
---

# ai-worker CLI selection

Scope: `app/services/stages/run_provider.rb`, `app/services/ai_cli/{rotation,providers,provider,agent_setting}.rb`, `app/services/ai_cli/provider/{claude,codex,cursor}.rb`, the settings screen, and their mirrored specs. Read the affected code: this is a map, not a substitute for it.

There are no app-managed project agents or subagents: no `Agent` records, delegations or per-stage agent. A project that wants subagents defines them in its own folder (e.g. `.claude/agents/`) and the agent CLI loads them itself; ai-worker neither lists nor orchestrates them.

## CLI selection and provider registry

- `Stages::RunProvider` is the single resolver for a stage run's CLI. Its precedence is: `workflow.rotation_provider!`, then `AiCli::AgentSetting.current`. `Stages::RunProvider.new(workflow:)` exposes only `override`: the rotation provider, or nil meaning `AiCli::Runner` falls back to the app-wide setting. Do not re-create this chain elsewhere.
- `AiCli::Rotation` holds per-provider nonnegative weights and a counter in `Rails.cache`; setting weights resets the counter. Default/all-zero is off; `next_provider` returns nil when off or advances through weighted slots. `Workflow#rotation_provider!` pins its one chosen provider; brainstorm and sync runs do not rotate.
- `AiCli::Providers` is the display-ordered registry. `names`, `find`, and raising `fetch` are its public lookup surface. Each stateless `Provider` has `name`, `Capabilities(tool_lists:, model:, effort:, mcp:)`, an argv builder, optional run wrapper, and outcome parser. `AiCli::AgentSetting.current(env: ENV)` reads a valid cached setting, otherwise `env["AGENT"]`, otherwise `claude` (specs pass `env:` a hash); its writer rejects unknown providers.

## Provider adapters

The production adapters select capabilities and delegate argv construction to `AiCli::Command::{Claude,Codex,Cursor}`; command-builder implementation remains with `ai-worker-cli-commands`. They are the selection-layer seam between the registry and those builders.

- `AiCli::Provider::Claude` passes the shared Claude options to its builder and parses Claude's final result event through `AiCli::ClaudeResult#final_outcome`.
- `AiCli::Provider::Codex` passes MCP, model, and effort options to its builder; its default outcome and wrapper remain the base provider behaviour.
- `AiCli::Provider::Cursor` keeps `Command::DEFAULT_EXECUTABLE_CHECK` and `Command::DEFAULT_HELP_PROBE` as injectable production seams, and wraps MCP runs with `CursorMcpFile`. `CursorMcpFile` itself remains owned by `ai-worker-browser-tests`.

## File map

- `app/services/ai_cli/provider/claude.rb` — Claude capabilities, builder delegation, and final-result outcome parsing.
- `app/services/ai_cli/provider/codex.rb` — Codex capabilities and builder delegation.
- `app/services/ai_cli/provider/cursor.rb` — Cursor capabilities, injectable command seams, and MCP-file run wrapping.
- `spec/services/ai_cli/provider/{claude,codex,cursor}_spec.rb` — mirrored adapter coverage for delegation, capabilities, outcomes, and wrapping.

## Settings screen

- `app/controllers/settings_controller.rb` — `update` writes `AiCli::AgentSetting.current` and re-renders with 422 on `ArgumentError`.
- `app/controllers/settings/rotations_controller.rb` — `update` sets `AiCli::Rotation.weights` and re-renders with 422 on `ArgumentError`.
- `app/controllers/concerns/settings_screen.rb` — loads agent and rotation settings and renders shared errors.
- `app/views/settings/show.html.erb` — renders the agent-setting and rotation-weight forms.

## Specs

Specs hit the real test `:memory_store` (cleared per example; see `ai-worker-testing`). Set state with `AiCli::AgentSetting.current=` / `AiCli::Rotation.weights=`; do not stub `Rails.cache` or those modules.

- `spec/services/stages/run_provider_spec.rb`: rotation override, workflow pinning, and nil override when rotation is off.
- `spec/services/ai_cli/rotation_spec.rb`: disabled default, weighted cycling, and invalid weights/providers.
- `spec/services/ai_cli/providers_spec.rb`: display order and `find`/`fetch` lookup.
- `spec/services/ai_cli/provider_spec.rb`: Provider's abstract builder plus default wrapper/outcome and `Capabilities` value object.
- `spec/services/ai_cli/provider/{claude,codex,cursor}_spec.rb`: each provider's delegated argv, capabilities, and outcome/wrapper behaviour (including Cursor's MCP file).
- `spec/services/ai_cli/agent_setting_spec.rb`: `current` fallback chain (cache > `AGENT` > `claude`), writer validation, and `available`.
- `spec/services/ai_cli/runner_spec.rb`: sets `AiCli::AgentSetting.current` explicitly so a developer's `AGENT` env cannot leak in.
- `spec/requests/settings_spec.rb`: agent-setting update and invalid-agent response.
- `spec/requests/settings/rotations_spec.rb`: rotation-weight update (assert `AiCli::Rotation.weights` after the request) and invalid-weight response.
