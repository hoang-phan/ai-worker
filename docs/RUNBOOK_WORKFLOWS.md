# Runbook workflows

A **runbook** workflow (`Workflow#kind = runbook`) is an ordered, user-defined list of stages instead of the
branch/PR/review lifecycle. It runs one stage, then stops in status `waiting` until someone clicks **Next**. Use it for
release days, deployments, onboarding checklists, or any repeatable multi-step process.

It is a workflow, not a project kind: a project (the thing being deployed) can have any number of runbook workflows,
one per deployment, each with its own stages and variables. Create one with **New runbook** on the project page.

## Model
- `Workflow#kind = runbook`, `current_stage_id`, `awaiting_next`, `variables` (JSON, edited as `NAME=value` lines).
- Its `Stage`s (`stage_type: runbook_step`) carry `name`, `position`, `run_mode` (`agent` | `message`), `channel`, `prompt`.
  Add, edit and remove them on the workflow page.
- To avoid retyping, **Start with the stages of** (new-runbook form) copies the stages of another runbook workflow of
  the same project. The copy is independent, so editing one run never changes another.
- **Clone** (runbook page) does the same in one click: a new pending runbook with the same stages and the variables you set
  up front (channel etc.); variables a stage emitted via `VAR:` lines (version, tag …) are not copied. Opened on the edit page to fill in before **Start**.

## Lifecycle
`pending` → **Start** → `implementing` (nothing runs yet: click **Run stage** once) → the stage runs → `waiting` (`awaiting_next`)
→ **Next** (`Workflow#advance!`) → next stage … → `done` after the last one.

Runs are semi-automatic. Per stage (edit form):
- **Continue automatically** (`auto_advance`): when the stage succeeds the workflow moves to the next stage itself and the
  scheduler starts it (`Workflow#auto_run`, set by **Run stage** / **Next**; the cron tick, or an immediate job, picks it up).
  Unticked, the runbook stops in `waiting` and a person clicks **Next** — that is the decision point. **Next** also starts the
  following stage, so no extra "Run" click. Auto-advance on the last stage finishes the workflow.
- **Wait for GitHub Actions workflow** (`wait_for_workflow`, e.g. `manual_environment_deploy.yml`): the stage doesn't start until
  the newest run of that workflow, started after the previous stage began, has completed successfully (`gh run list`, repo = the
  `REPO` variable or the project's). Re-checked every tick, logged once (`waiting_for_check`, then `check_passed`). A completed
  run that failed fails the stage.
A failure stops the chain (`auto_run` cleared): the stage stays `implementing`; click **Run stage** to retry (`errored` after 3, **Resume**).
`waiting` is ignored by the scheduler; runbook workflows don't hold a project's one-at-a-time slot (they still respect the
one-agent-per-clone and global concurrency limits). Defaults keep the old behaviour (stop after every stage, no check); both
settings are copied when a runbook is cloned.

## Stage modes
- `agent`: the rendered prompt is run as is.
- `message`: the agent is asked to post the rendered text to the Slack `channel` with its Slack MCP connector and
  reply `POSTED`; without that line the stage fails.

## Placeholders
`{NAME}` tokens are replaced in one pass by `Prompts::Renderer`. Built-ins: `{JIRA} {PR} {REVIEWER} {SKILLS}
{IMAGES} {TASK} {SLACK} {TESTER}`, plus `{STAGE_NAME}`, `{STARTED_ON}` (the date the workflow was created, dd/mm/yyyy, Brisbane time) and `{PREV_OUTPUT}` (the previous stage's output, last
3000 chars). Any other name is a workflow variable (the workflow's non-blank values). Built-ins win
over a same-named variable. Unknown tokens are left untouched. The stage form's template picker fills from
`Prompts::Renderer.placeholders_for(workflow)`.

An agent stage can set variables for later stages by printing lines such as `VAR: VERSION=2.21.1-f839742`.
For a multi-line value (a long list), print `VAR_BEGIN: NAME`, the lines, then `VAR_END`; it is stored whole (no 3000-char
cap, unlike `{PREV_OUTPUT}`). In the variables box a newline in a value is shown as `\n`.

Release testing list: stage 1 (`db/seeds/release_notes_prompt.md`) fetches the draft release's "To be tested" items with
`gh`, drops no-ticket / NOT TESTABLE / test-infra / devops / bot items, and emits `{RELEASE_ITEMS}`; stage 2 posts it.

## Example
`db/seeds.rb` seeds a "Recruit" project with a pending "template" runbook workflow (review notes → comms → tickets →
find build version → comms…); copy it for each release. Set `RECRUIT_DIR` before seeding to choose the agent's working
directory. Steps that need a human (GitHub deploy freeze, Manual Deploy) are deliberately left to the person between stages.
