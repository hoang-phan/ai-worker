---
name: ai-worker-project-agents
description: Applies ai-worker's project-agent discipline. Use for app/models/agent.rb, agent_delegation.rb and stage.rb; app/controllers/agents_controller.rb; agent/project/stage views; agent prompt sections; app/services/stages/run_provider.rb; app/services/ai_cli/{rotation,providers,provider,agent_setting}.rb; and their listed specs.
---

# ai-worker project agents

Scope: `app/models/{agent,agent_delegation,stage}.rb`, `app/controllers/agents_controller.rb`, `app/views/agents/_form.html.erb`, `app/views/projects/_agents.html.erb`, `app/views/stages/form/_prompt_fields.html.erb`, `app/services/prompts/stage_sections/{agent_brief,subagents}.rb`, `app/services/stages/run_provider.rb`, `app/services/ai_cli/{rotation,providers,provider,agent_setting}.rb`, and their specs. Read the affected code: this is a map, not a substitute for it.

## Model and ownership

- `Agent` is a specialist owned by exactly one `Project`; names are unique within that project. `description` is required. `NAME_FORMAT` accepts lowercase slug names (`billing-expert`); `MODEL_FORMAT` allows only word characters, `.`, `-`, and `[]`; `EFFORTS` is `low`, `medium`, `high`, `xhigh`, `max`. Blank model/effort use CLI defaults.
- `provider` is optional and must be in `AiCli::Providers.names`; blank defers CLI selection. `allowed_tools` is JSON, defaulting to `[]` (no restriction). `allowed_tools_text` reads/writes one trimmed rule per line, dropping blanks and duplicates.
- An agent has many `stages` (`dependent: :nullify`), `agent_delegations`, and `delegates` through them. It also has reverse `delegating_links`; both delegation associations destroy their join rows. `AgentDelegation` belongs to `agent` and `delegate` (both Agents) and makes `delegate_id` unique per `agent_id` (also a DB index).
- The invariant is enforced on `Agent`: every delegate belongs to the same project and cannot be the agent itself. Agents and delegates therefore never cross projects.
- `Stage` optionally belongs to an `agent`; `agent_belongs_to_workflow_project` rejects an agent whose project differs from `workflow.project`.

## UI and assignment

- `AgentsController` includes `ProjectScoped` then `ProjectChildCrud`, configuring `:agents` and the "Agent" flash label. It remains project-scoped CRUD only: success redirects to the project with a notice; invalid create/update re-renders with 422; the concern scopes lookups through `@project.agents`.
- `agent_params` permits name, description, instructions, model, effort, provider, `allowed_tools_text`, and `delegate_ids`; it filters delegates through `@project.agents`, so forged foreign IDs cannot be linked.
- `agents/_form` exposes identity/brief, optional model/effort/provider, line-based allowed tools, instructions, and other same-project agents as delegation checkboxes. Provider choices come from `AiCli::Providers.names` and the blank label states the current `AiCli::AgentSetting`.
- `projects/_agents` lists agents with CLI/model/effort and delegate names, plus project-scoped CRUD links. `stages/form/_prompt_fields` shows the agent select only when the project has agents; a blank assignment means no project agent.

## Prompt brief and delegation

- `Prompts::StageSections::AgentBrief` is prepended only for a stage agent. It identifies the agent, passes its instructions as project-owner data rather than overriding task instructions, and states `allowed_tools` only when the selected provider cannot enforce tool lists.
- `Subagents` is separate from project agents: for `implementation`, `simple_implementation`, `pr_check`, and `task`, it lists `.claude/agents` roster entries and asks the running agent to delegate focused, complete briefs and verify returned work. It is empty for other stage types or no entries.
- Invariant: only providers whose `capabilities.tool_lists` are true enforce `allowed_tools`; all other providers receive the restriction in `AgentBrief` as prompt guidance.

## CLI selection and provider registry

- `Stages::RunProvider` is the single resolver for a stage run's CLI. Its precedence is: stage agent's nonblank provider, then `workflow.rotation_provider!`, then `AiCli::AgentSetting.current`. `override` is the first two (nil means app-wide); `name` includes the fallback; `provider` resolves the descriptor. Do not re-create this chain elsewhere.
- `AiCli::Rotation` holds per-provider nonnegative weights and a counter in `Rails.cache`; setting weights resets the counter. Default/all-zero is off; `next_provider` returns nil when off or advances through weighted slots. `Workflow#rotation_provider!` pins its one chosen provider; brainstorm and sync runs do not rotate.
- `AiCli::Providers` is the display-ordered registry. `names`, `find`, and raising `fetch` are its public lookup surface. Each stateless `Provider` has `name`, `Capabilities(tool_lists:, model:, effort:, mcp:)`, an argv builder, optional run wrapper, and outcome parser. `AgentSetting.current` reads a valid cached setting, otherwise `AGENT`, otherwise `claude`; its writer rejects unknown providers.

## Adding an Agent field

1. Add a focused migration and schema change; choose explicit null/default semantics where needed.
2. Add model behavior and validation in `Agent`.
3. Permit the field in `AgentsController#agent_params`.
4. Add it to `agents/_form` and, if useful, `projects/_agents`.
5. Thread it into `AgentBrief` (and `StagePrompt`) when it affects the run prompt.
6. Update model, request, and prompt-section specs; add resolver/CLI specs if it changes selection or provider options.

## Specs

- `spec/models/agent_spec.rb`: formats, scoped uniqueness, model/effort/provider validation, delegation invariants and cleanup, stage nullification, allowed-tools text.
- `spec/models/agent_delegation_spec.rb`: join associations, presence, directionality, and uniqueness.
- `spec/requests/agents_spec.rb`: project page/list and forms, CRUD, strong-parameter foreign-delegate filtering, provider/tools form behavior and project scoping.
- `spec/services/stages/run_provider_spec.rb`: agent-provider > rotation > app setting precedence and workflow pinning.
- `spec/services/prompts/stage_sections/agent_brief_spec.rb`: brief/data framing and provider-dependent tool wording; `subagents_spec.rb`: eligible types, empty guards, roster and delegation guidance.
- `spec/services/ai_cli/rotation_spec.rb`: disabled default, weighted cycling, and invalid weights/providers.
