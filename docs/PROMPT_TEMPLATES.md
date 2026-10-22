# Prompt templates

`PromptTemplate#body` is plain text containing any of these placeholders,
substituted by `Prompts::Renderer` at execution time:

| Placeholder | Filled with | Notes |
|---|---|---|
| `{JIRA}` | `workflow.jira_ticket` | e.g. `ENG-1234` |
| `{PR}` | `workflow.github_pr_url` | blank during the `implementation` stage (no PR exists yet) |
| `{REVIEWER}` | `workflow.github_reviewer` | one or more GitHub usernames, comma-separated (`gh pr create --reviewer` accepts this form) |
| `{PR_SKILLS}` | `workflow.pr_skill_list.join(", ")` | Same format, from `project.default_pr_skills`: the skills only the `pr_create` stage's prompt uses. `{SKILLS}` stays for implementation. |
| `{SKILLS}` | `workflow.skill_list.join(", ")` | comma-separated Claude Code skill names, from the target project's own `.agents/skills/` — see `docs/ADDING_A_PROJECT.md` |
| `{TESTER}` | `project.jira_tester` | Jira user to assign UAT tickets to (`jira_update` stages) |
| `{UAT_URL}` | `project.uat_url` | The project's UAT site (`uat_test` stages). The UAT login is not a placeholder: it reaches the agent as the `UAT_USERNAME` / `UAT_PASSWORD` environment variables. |
| `{LOCAL_URL}` / `{LOCAL_INSTRUCTIONS}` | `project.local_url` / `project.local_instructions` | Local development server URL and local-only instructions (`local_test` stages). |
| `{CI_INSTRUCTIONS}` | `project.ci_instructions` | Project-specific pre-push checks (e.g. `bin/ci`, or `pnpm test`). Used by the Implement and Review Fix templates; empty if the project has none. |
| `{PR_INSTRUCTIONS}` (`project.pr_instructions`, the `pr_create` stage) / `{CI_COMMAND}` / `{CI_OUTPUT}` / `{CI_STATUS}` / `{CI_VERIFY_INSTRUCTIONS}` | `project.ci_command` / the last check's log path / its exit status / `project.ci_verify_instructions` | The check/verify loop (`ci_verify` stages). |
| `{TEST_INSTRUCTIONS}` | `project.test_instructions` | Free-text instructions valid on every environment (UAT and local): login, test data, guide to read; blank if none. |
| `{UAT_INSTRUCTIONS}` | `project.uat_instructions` | Free-text, per-project instructions for the UAT test (login quirks, test data, a guide to read); blank if none (`uat_test` stages). |
| `{SLACK}` | `workflow.slack_url` | permalink of the Slack message that mentioned the PR (`pr_review` stages only) |
| `{IMAGES}` | `workflow.image_paths.join(", ")` | absolute paths of the reference images uploaded on the workflow (plain files under `tmp/workflow_images/<workflow id>/`, deleted with the workflow); blank if none |
| `{TASK}` | `workflow.task_description` | The free-text task description; blank if none. |
| `{STARTED_ON}` | `workflow.created_at` | Date the workflow was created, dd/mm/yyyy, Brisbane time. |
| `{STAGE_NAME}` | `workflow.current_stage.display_name` | Name of the current stage. |
| `{PREV_OUTPUT}` | previous runbook stage's output | Last 3000 characters of what the previous stage's agent printed (runbook workflows). |

Exactly one `PromptTemplate` per `stage_type` should have `active: true` —
that's the default a `Stage` uses when it doesn't have a `prompt_template_id`
of its own (`Stage#effective_template`).

## Appended sections

`Prompts::StagePrompt` appends conditional sections (`Prompts::StageSections`) after the rendered body. One of them,
`Subagents`, applies to `implementation`, `simple_implementation`, `pr_check` and `task` stages: it lists the
subagents the project defines in `<local_directory>/.claude/agents/*.md` (`name` and `description` from the YAML
frontmatter, read by `Prompts::SubagentRoster`; at most 20, sorted by name, descriptions cut to ~200 characters) and
tells the agent to delegate focused, self-contained sub-tasks to them with a complete brief and to verify what they
return. Nothing is added when the project has no subagents. The list is data from the repo, not instructions.

## Example: `implementation` template

```
Implement Jira ticket {JIRA} in this repository.

Use the following skill(s) to scope your work and avoid reading the whole
codebase: {SKILLS}. If none of them cover the ticket, say so instead of
guessing at unrelated files.

When the implementation is complete and committed on the current branch:
1. Push the branch: git push -u origin HEAD
2. Open a PR: gh pr create --fill --reviewer {REVIEWER}
3. Print the PR URL as the last line of your output.
```

## Example: `pr_check` template

```
PR {PR} for Jira ticket {JIRA} has requested changes. Use the following
skill(s) to scope your work: {SKILLS}.

1. Fetch the review feedback: gh pr view {PR} --json reviews,comments
2. Address every comment. Commit and push the fixes to the current branch.
3. Re-request review from {REVIEWER} (comma-separated if more than one):
   gh pr edit {PR} --add-reviewer {REVIEWER}
   (OWNER/REPO/NUMBER can be read off of {PR}'s URL: github.com/OWNER/REPO/pull/NUMBER)
```

Note: `ai-worker` itself also calls `gh api .../requested_reviewers`
directly from `Github::Client#request_review!` after this run finishes —
the template's own re-request step is a safety net in case Claude's run
doesn't get to it, not the only place it happens.

## Runbook placeholders

`{STAGE_NAME}`, `{PREV_OUTPUT}` and any workflow variable (`{VERSION}`, `{ENV}`, ...) are available too; see `docs/RUNBOOK_WORKFLOWS.md`.
