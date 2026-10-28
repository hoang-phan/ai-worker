---
name: ai-worker-agent-output
description: Owns ai-worker pure parsers for a finished agent run's log. Use for app/services/ai_cli/{output,claude_result,run_verdict}.rb or spec/services/ai_cli/{output,claude_result,run_verdict}_spec.rb.
---

# ai-worker agent output parsers

Owns the pure parsers that interpret a finished agent run's log. Process launch, polling, stale handling, and log I/O stay in `ai-worker-agent-cli`. Adding a new stage result marker: `ai-worker-stage-types`. Default prompt text that asks the agent to print a marker: `ai-worker-prompts`; appended section wording: `ai-worker-stage-sections`.

## File map

- `app/services/ai_cli/output.rb` — `AiCli::Output.new(text)`, pure stage-marker parser: `variables` (`VAR:` / `VAR_BEGIN`..`VAR_END`), `jira_result`, `uat_result`, `local_test_result`, `ci_verdict`, `retest_requested?` (missing counts as YES), `local_test_feedback_block`, `fixed_summary`, `lessons`, `follow_ups` (rows cleaned by `Workflows::ProposalNormalizer`), `posted?`. Claude stream-json result parsing belongs to `AiCli::ClaudeResult`.
- `app/services/ai_cli/claude_result.rb` — `AiCli::ClaudeResult.new(text)`, pure provider-format parser for claude's stream-json log: `result_event` (last valid `{"type":"result"}` line starting with `{`; malformed/non-result lines skipped) and `final_outcome` (`:error` if `is_error` truthy, else `:success`; nil without an event). Stage markers stay in `AiCli::Output`.
- `app/services/ai_cli/run_verdict.rb` — `AiCli::RunVerdict.new(exit_status:, output:, agent:, pid:).verify!` (pure, no I/O): returns the output or raises `AiCli::CommandError`. A nil status (reaped elsewhere) is judged from the final claude result event; no result event means failed.
- `spec/services/ai_cli/output_spec.rb` — every stage marker incl. missing.
- `spec/services/ai_cli/claude_result_spec.rb` — result event / final outcome parsing.
- `spec/services/ai_cli/run_verdict_spec.rb` — exit-status and nil-status verdict paths.

## Conventions

- **Pure parsers only.** `Output`, `ClaudeResult`, and `RunVerdict` take text (and for `RunVerdict`, exit status / agent / pid); they do no file or process I/O and hold no workflow state.
- **First match vs last match.** `jira_result`, `uat_result`, and `local_test_result` take the first matching marker line. Other markers and blocks take the last match, because the log may echo the prompt's own example (`ci_verdict`, `LOCAL_RETEST`, feedback / fixed-summary / lessons / follow-ups blocks).
- **Anchored vs unanchored blocks.** `lessons` and `follow_ups` scan `BEGIN`/`END` with line anchors (`^[ \t]*...[ \t]*$`). `local_test_feedback_block` and `fixed_summary` use the unanchored form (markers may sit mid-line / mid-log).
- **Missing `LOCAL_RETEST` counts as YES.** `retest_requested?` is false only when the last marker is explicitly `NO`.
- **`follow_ups` is cleaned by `Workflows::ProposalNormalizer`.** Invalid or non-array JSON becomes `[]`.
- **`RunVerdict` on a nil exit status** asks the provider for an outcome from the log (claude: the final result event). A missing outcome is treated as failed; `:error` raises `AiCli::CommandError`.
- **`ClaudeResult` is the provider-format parser;** stage markers (`JIRA_RESULT`, `UAT_RESULT`, blocks, …) stay in `Output`. Callers that need a result event or final outcome use `AiCli::ClaudeResult` directly.
- New markers: add the method and spec here, follow the checklist in `ai-worker-stage-types`, and put the ask-for-marker wording in `ai-worker-prompts` or `ai-worker-stage-sections` as applicable.

## Specs

- `RAILS_ENV=test bundle exec rspec spec/services/ai_cli/{output,claude_result,run_verdict}_spec.rb`
