---
name: ai-worker-cli-selection
description: Selects the agent CLI and provider for a run — rotation (AiCli::Rotation, Workflow#rotation_provider!), the app-wide AgentSetting fallback and the AiCli::Providers registry, resolved by Stages::RunProvider. Use for app/services/stages/run_provider.rb; app/services/ai_cli/{rotation,providers,provider,agent_setting}.rb; app/controllers/{settings_controller,settings/rotations_controller}.rb; app/controllers/concerns/settings_screen.rb; app/views/settings/show.html.erb; and their listed specs.
---

# ai-worker CLI selection

Scope: `app/services/stages/run_provider.rb`, `app/services/ai_cli/{rotation,providers,provider,agent_setting}.rb`, the settings screen, and their specs. Read the affected code: this is a map, not a substitute for it.

There are no app-managed project agents or subagents: no `Agent` records, delegations or per-stage agent. A project that wants subagents defines them in its own folder (e.g. `.claude/agents/`) and the agent CLI loads them itself; ai-worker neither lists nor orchestrates them.

## CLI selection and provider registry

- `Stages::RunProvider` is the single resolver for a stage run's CLI. Its precedence is: `workflow.rotation_provider!`, then `AiCli::AgentSetting.current`. `Stages::RunProvider.new(workflow:)` exposes only `override`: the rotation provider, or nil meaning `AiCli::Runner` falls back to the app-wide setting. Do not re-create this chain elsewhere.
- `AiCli::Rotation` holds per-provider nonnegative weights and a counter in `Rails.cache`; setting weights resets the counter. Default/all-zero is off; `next_provider` returns nil when off or advances through weighted slots. `Workflow#rotation_provider!` pins its one chosen provider; brainstorm and sync runs do not rotate.
- `AiCli::Providers` is the display-ordered registry. `names`, `find`, and raising `fetch` are its public lookup surface. Each stateless `Provider` has `name`, `Capabilities(tool_lists:, model:, effort:, mcp:)`, an argv builder, optional run wrapper, and outcome parser. `AgentSetting.current` reads a valid cached setting, otherwise `AGENT`, otherwise `claude`; its writer rejects unknown providers.

## Settings screen

- `app/controllers/settings_controller.rb` — `update` writes `AiCli::AgentSetting.current` and re-renders with 422 on `ArgumentError`.
- `app/controllers/settings/rotations_controller.rb` — `update` sets `AiCli::Rotation.weights` and re-renders with 422 on `ArgumentError`.
- `app/controllers/concerns/settings_screen.rb` — loads agent and rotation settings and renders shared errors.
- `app/views/settings/show.html.erb` — renders the agent-setting and rotation-weight forms.

## Specs

- `spec/services/stages/run_provider_spec.rb`: rotation override, workflow pinning, and nil override when rotation is off.
- `spec/services/ai_cli/rotation_spec.rb`: disabled default, weighted cycling, and invalid weights/providers.
- `spec/services/ai_cli/providers_spec.rb`: display order and `find`/`fetch` lookup.
- `spec/services/ai_cli/provider_spec.rb`: Provider's abstract builder plus default wrapper/outcome and `Capabilities` value object.
- `spec/services/ai_cli/provider/{claude,codex,cursor}_spec.rb`: each provider's argv, capabilities, and outcome/wrapper behaviour (including Cursor's MCP file).
- `spec/services/ai_cli/agent_setting_spec.rb`: `current` fallback chain (cache > `AGENT` > `claude`), writer validation, and `available`.
- `spec/requests/settings_spec.rb`: agent-setting update and invalid-agent response.
- `spec/requests/settings/rotations_spec.rb`: rotation-weight update and invalid-weight response.
