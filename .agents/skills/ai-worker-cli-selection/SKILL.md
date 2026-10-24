---
name: ai-worker-cli-selection
description: Selects the agent CLI and provider for a run — rotation (AiCli::Rotation, Workflow#rotation_provider!), the app-wide AgentSetting fallback and the AiCli::Providers registry, resolved by Stages::RunProvider. Use for app/services/stages/run_provider.rb; app/services/ai_cli/{rotation,providers,provider,agent_setting}.rb; and their listed specs.
---

# ai-worker CLI selection

Scope: `app/services/stages/run_provider.rb`, `app/services/ai_cli/{rotation,providers,provider,agent_setting}.rb`, and their specs. Read the affected code: this is a map, not a substitute for it.

There are no app-managed project agents or subagents: no `Agent` records, delegations or per-stage agent. A project that wants subagents defines them in its own folder (e.g. `.claude/agents/`) and the agent CLI loads them itself; ai-worker neither lists nor orchestrates them.

## CLI selection and provider registry

- `Stages::RunProvider` is the single resolver for a stage run's CLI. Its precedence is: `workflow.rotation_provider!`, then `AiCli::AgentSetting.current`. `override` is the first (nil means app-wide); `name` includes the fallback; `provider` resolves the descriptor. Do not re-create this chain elsewhere.
- `AiCli::Rotation` holds per-provider nonnegative weights and a counter in `Rails.cache`; setting weights resets the counter. Default/all-zero is off; `next_provider` returns nil when off or advances through weighted slots. `Workflow#rotation_provider!` pins its one chosen provider; brainstorm and sync runs do not rotate.
- `AiCli::Providers` is the display-ordered registry. `names`, `find`, and raising `fetch` are its public lookup surface. Each stateless `Provider` has `name`, `Capabilities(tool_lists:, model:, effort:, mcp:)`, an argv builder, optional run wrapper, and outcome parser. `AgentSetting.current` reads a valid cached setting, otherwise `AGENT`, otherwise `claude`; its writer rejects unknown providers.

## Specs

- `spec/services/stages/run_provider_spec.rb`: rotation > app setting precedence and workflow pinning.
- `spec/services/ai_cli/rotation_spec.rb`: disabled default, weighted cycling, and invalid weights/providers.
- `spec/services/ai_cli/providers_spec.rb`: display order, `find`/`fetch` lookup, and each provider's capabilities.
- `spec/services/ai_cli/provider/provider_spec.rb`: per-provider argv builder, run wrapper (cursor MCP file) and outcome parsing.
- `spec/services/ai_cli/agent_setting_spec.rb`: `current` fallback chain (cache > `AGENT` > `claude`), writer validation, and `available`.
