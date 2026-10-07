# Prompt templates

`PromptTemplate#body` is plain text containing any of these placeholders,
substituted by `Prompts::Renderer` at execution time:

| Placeholder | Filled with | Notes |
|---|---|---|
| `{JIRA}` | `workflow.jira_ticket` | e.g. `ENG-1234` |
| `{PR}` | `workflow.github_pr_url` | blank during the `implementation` stage (no PR exists yet) |
| `{REVIEWER}` | `workflow.github_reviewer` | one or more GitHub usernames, comma-separated (`gh pr create --reviewer` accepts this form) |
| `{SKILLS}` | `workflow.skill_list.join(", ")` | comma-separated Claude Code skill names, from the target project's own `.claude/skills/` — see `docs/ADDING_A_PROJECT.md` |
| `{IMAGES}` | `workflow.image_paths.join(", ")` | absolute paths of the reference images uploaded on the workflow (plain files under `tmp/workflow_images/<workflow id>/`, deleted with the workflow); blank if none |

Exactly one `PromptTemplate` per `stage_type` should have `active: true` —
that's the default a `Stage` uses when it doesn't have a `prompt_template_id`
of its own (`Stage#effective_template`).

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
