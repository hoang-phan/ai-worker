---
name: ai-worker-refactoring
description: Use for any task that extracts, splits, slims or moves code without changing behaviour.
---

# ai-worker refactoring

Use this skill for behaviour-preserving structural work. It complements the skill that owns the affected subsystem; that owning skill remains authoritative for its file map, invariants, data rules, API contracts, and focused verification.

## Placement and seams

- Extract model logic into a focused PORO under `app/models/<plural>/` (for example, `app/models/workflows/`); extract service logic into `app/services/<namespace>/`. Keep one class per file, with the file path matching the constant.
- Put each formerly inline error class in its own matching file. Do not leave a duplicate compatibility definition behind.
- Keep the original public API stable: leave a thin `delegate` or one-line forwarder on the original class and keep callers unchanged unless the task explicitly asks to change them.
- Inject collaborators by keyword with production defaults, so production preserves existing wiring and specs can pass doubles. Follow the established patterns in `StageExecutor`, `Brainstorm::Planner`, and `Slack::ReviewNotifier`.
- Preserve the surrounding comment density, terminology, and naming. Move explanatory comments with the code they explain; do not use a refactor to rewrite documentation or style.

## Reuse before you extract

Before creating a new class, grep for an existing seam below and extend it instead of duplicating. If you create a new shared seam, add it to this list in the same commit.

- `Stages::CollaboratorFactory` — start/finish dispatch-table entry builder (`ai-worker-stage-pipeline`)
- `AgentRuns::SyncCycle` + `AgentRuns::CycleSource` — detached sync job poll/import/start (`ai-worker-detached-agent-runs`)
- `AiCli::DetachedRun` — detached agent run with JSON result file (`ai-worker-detached-agent-runs`)
- `AgentRuns::ManualStart.for(source)` + `ManualStartFlash` — "run now" buttons wired from a `CycleSource` (`ai-worker-detached-agent-runs`, `ai-worker-ui`)
- `AgentRuns::Cadence` — due-time logic (`ai-worker-detached-agent-runs`)
- `AgentRuns::ImportResult` — Jira/Slack import result collections, summaries, and save outcome recording (`ai-worker-detached-agent-runs`)
- `AgentRuns::StateRoot` — on-disk state dirs under `config.x.state_root` (`ai-worker-detached-agent-runs`)
- `ProjectChildCrud` / `ProjectScoped` / `ProjectMemberScoped` / `WorkflowScoped` / `SettingsScreen` — controller concerns (`ai-worker-ui`; `WorkflowScoped` → `ai-worker-workflow-screens`)
- `Projects::WorkflowDefaults` — new workflow attributes (`ai-worker-domain`)
- `Workflows::SummaryKey` and `Workflows::ProposalNormalizer` — proposal dedupe and agent proposal rows (`ai-worker-proposal-imports`)
- `AiCli::Output` — result markers (`ai-worker-agent-output`)
- `Prompts::Renderer` + `Prompts::StageSections` — prompt text (`ai-worker-prompts`)
- `Github::Runner` — `gh` subprocesses (`ai-worker-github`); `Git::Shell` — `git` subprocesses (`ai-worker-git`)
- `spec/support` helpers (`RecordHelper`, `let_tmpdir`, `FakeDetachedRun`, `GitRepoHelper`, `StageRunHelper`, `active_job_test_adapter`) — shared spec setup (`ai-worker-testing`)
- Structural spec guards are owned by `ai-worker-spec-guards`.

## Specs and file maps

- When a refactor adds or moves files, update the owning skill's file map and follow `ai-worker-skills`.
- Structural ratchets and their ALLOWLIST rules are owned by `ai-worker-spec-guards`.
- Move examples with the extracted code: add one spec file per new class and slim the original spec to orchestration/public-delegation coverage. Preserve all coverage; compare `rspec --dry-run` example counts before and after the move.

## Guardrails

- Do not change behaviour while extracting, splitting, slimming, or moving code.
- Do not rename persisted enums or `StageRun::ACTIONS`; do not add, remove, reorder, or otherwise alter their meanings. Those rules are owned by `ai-worker-domain` and, where applicable, `ai-worker-stage-types`.
- Do not make database, migration, or schema changes. Do not run scratch scripts, `bin/rails runner`, or console commands against the development database; data safety and spec setup are owned by `ai-worker-testing` and `ai-worker-domain`.

## Verification

- Run `RAILS_ENV=test bundle exec rspec` for the touched spec directories (and compare dry-run counts when examples move).
- Run `bin/rubocop`.
- Also run the focused checks required by the owning skill.
