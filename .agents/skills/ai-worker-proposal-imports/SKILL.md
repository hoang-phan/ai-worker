---
name: ai-worker-proposal-imports
description: Owns normalization and import of agent-proposed workflows. Use for Workflows::ProposalNormalizer, ProposalWorkflow, SummaryKey, Brainstorm::ProposalImporter, Stages::FollowUpImporter, or their mirrored specs.
---

# ai-worker-proposal-imports

Scope: `app/models/workflows/{proposal_normalizer,proposal_workflow,summary_key}.rb`, `app/services/brainstorm/proposal_importer.rb`, `app/services/stages/follow_up_importer.rb`, and `spec/models/workflows/{proposal_normalizer,proposal_workflow,summary_key}_spec.rb`, `spec/services/brainstorm/proposal_importer_spec.rb`, and `spec/services/stages/follow_up_importer_spec.rb`.

This skill owns the shared seams and the deliberately different importing policies. Read the code and its mirrored specs before changing a policy. Brainstorm lifecycle/prompt/job work remains `ai-worker-brainstorm`; task-stage completion remains `ai-worker-stage-pipeline`; result-marker parsing remains `ai-worker-agent-cli`; general model/enum rules remain `ai-worker-domain`.

## Shared seams

- `Workflows::ProposalNormalizer.call(rows)` is pure. It accepts only Hash rows, returns only `{ "summary", "task" }` plus optional `"skills"`, drops blank summary/task rows, squishes and truncates summaries to `Workflow::SUMMARY_LENGTH`, and strips/truncates tasks to `TASK_LENGTH` (4000). Skills accept an Array or comma-delimited string; retain valid `/\A[\w:.\-\/]+\z/` names only, dedupe, cap at six, join with `", "`, and omit the key when none remain. Both brainstorm `result.json` rows and `AiCli::Output#follow_ups` use it.
- `Workflows::SummaryKey.call(text)` is the common comparison key: lowercase, collapse non-alphanumerics to spaces, then strip. `.set(workflows)` returns the Set of keys from workflow briefs. Do not give the importers distinct normalization rules.
- `Workflows::ProposalWorkflow.new(project).build(proposal, merge_skills:)` returns an unsaved development workflow with the proposal summary/task, `project.next_workflow_position`, and status resolved by `project.brainstorm_auto_start?` (`implementing` or `pending`). It does not take `status:`. With `merge_skills: true`, defaults come first and proposal skills are appended, blank entries removed and names deduped; without it, use project defaults alone.
- New proposal fields change the normalizer, both import inputs/prompts that expose the field, builder, and their focused specs together. Do not make the importers uniform merely because they share these seams.

## Brainstorm import

`Brainstorm::ProposalImporter.new(project, in_flight:).call(proposals)` returns `Result(created:, skipped:)`; `summary` is `"created N, skipped M"`.

- Its queue gate is strict: if any `project.workflows.queued` workflow exists, return empty `created` and `skipped`. The planner's wait gate has the same purpose; implementing workflows themselves do not block import.
- Seed known keys only from the injected `in_flight` workflows. A matching in-flight brief or earlier successfully-created proposal is skipped, with its summary in `skipped`.
- Stop once `created.size` reaches `project.brainstorm_max_workflows`; skipped proposals do not consume the cap.
- Build with `merge_skills: true`. The builder, not the importer, chooses pending versus implementing from `brainstorm_auto_start?`.
- Reserve a dedupe key only after `workflow.save` succeeds. A validation failure therefore reports `"summary (full error sentence)"` in `skipped` and does not reserve that key for a later row.

## Follow-up import

`Stages::FollowUpImporter.new(project).call(proposals)` returns only the summaries of successfully created workflows.

- There is no queued-workflow gate. Seed known keys from every project workflow except `done` ones, so done work may be proposed again.
- The independent cap is `MAX_FOLLOW_UPS` (2) successful creations; ignored rows and failed saves do not increment it.
- Build with `merge_skills: false`, so proposal-supplied skills never alter the project's defaults. As above, the builder resolves pending versus implementing.
- Reserve the key with `known.add?` before building or saving. That rejects later batch duplicates even if the first row fails validation; a failed save is omitted silently from the returned array. Preserve this timing rather than aligning it with Brainstorm.

## Boundaries and verification

- Do not change agent proposal formats, CLI argument builders, or the broader Brainstorm/stage execution policies while working here.
- Cover the shared normalizer, key and builder contracts in their model specs; cover each importer's own gate, known-workflow set, cap, skill mode, return shape, validation handling, and dedupe-reservation timing in its service spec.
- Run `RAILS_ENV=test bundle exec rspec spec/skills` when changing skill routing or file maps. Run the five mirrored specs for behavior changes.
