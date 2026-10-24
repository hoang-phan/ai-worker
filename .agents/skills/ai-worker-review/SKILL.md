---
name: ai-worker-review
description: Pre-PR local review for ai-worker, covering subprocess safety, stage/enum invariants, and audit-log completeness. Use before opening a PR against this repo.
argument-hint: '[--base <ref>] [--staged | --working]'
---

# ai-worker-review

Reviews the diff against `main` (or `--staged` / `--working` if passed) using `git -C <repo> diff <args>` — never `cd <repo> && git diff`, for the same non-interactive-safety reason the app's own services avoid `cd &&` strings.

1. Get the diff: `git -C . diff main...HEAD` (or the requested range).
2. Load `assets/review-checklist.md` — the stable, rarely-changing review criteria for this app.
3. For each changed file, find its owning skill in the table below (first match wins) and re-read *that skill* fresh, rather than trusting this review's memory of the codebase. Skill descriptions list the exact files each one owns.

   | Changed path | Skill |
   | --- | --- |
   | `app/services/stages/{simple_implementation_finish,pr_opened_finish,ci_check_finish,ci_verify_finish}.rb`, `app/models/workflows/ci_loop_resume.rb`, ci rounds in `app/models/stages/run_history.rb`, `app/services/prompts/defaults/{ci_verify,pr_create,simple_implementation}.md`, `app/views/projects/form/_ci_loop.html.erb`, `spec/support/ci_loop_helper.rb`, or a ci_loop-flow change | `ai-worker-ci-loop` |
   | `app/services/ai_cli/{browser_test_run,cursor_mcp_file}.rb`, `app/services/stages/{browser_test_start,local_test_policy,local_test_finish,uat_test_finish}.rb`, `app/services/scheduling/uat_phase.rb`, `app/services/prompts/stage_sections/local_feedback.rb`, `app/services/prompts/defaults/{uat_test,local_test}.md`, `app/views/projects/form/{_uat_test,_local_test}.html.erb`, or their listed specs | `ai-worker-browser-tests` |
   | runbook parts of `app/models/workflows/{runbook_navigator,runbook_clone,stage_seeder,stage_outputs,variables,current_stage,transitions}.rb` or `app/models/stage.rb`; `app/services/stages/{runbook_step_finish,workflow_run_gate}.rb`; the runbook branch of `start_handler.rb`; `Prompts::StagePrompt#slack_message`; runbook controllers/views; or their listed specs | `ai-worker-runbooks` |
   | `app/services/slack/{mention_fetcher,mention_prompt,mention_rows,review_sync,review_cycle_source,review_candidate,review_importer,fetch_error}.rb`, `app/jobs/slack_review_job.rb`, slack_review schedule entries, `project_slack_syncs_controller.rb`, listed Slack-review views, `app/services/stages/{pr_review_start,pr_review_finish}.rb`, `app/services/prompts/defaults/pr_review.md`, PR-review workflow details, or their specs | `ai-worker-pr-review-workflows` |
   | `app/models/workflows/{transitions,resume_status,ci_loop_resume,current_stage,stage_resolver,stage_seeder}.rb`, the transitions delegate or `current_stage` in `app/models/workflow.rb`, `workflow_transitions_controller.rb`, or their listed specs | `ai-worker-workflow-lifecycle` |
   | `projects_controller.rb` index/show, `workflow_positions_controller.rb`, `app/models/projects/{workflow_list,workflow_reorder}.rb`, project dashboard views/helpers, or their listed specs | `ai-worker-project-dashboard` |
   | per-project settings in `project.rb`, `ProjectsController#project_params/create/update`, project form views, `project_placeholders.rb`, listed project specs, or `docs/ADDING_A_PROJECT.md` | `ai-worker-project-settings` |
   | `app/controllers/{workflows,workflow_runbooks,workflow_images,workflow_time_logs,stages}_controller.rb`, `app/controllers/concerns/workflow_scoped.rb`, listed workflow/stage helpers, views, template-fill controller, or their request/helper specs | `ai-worker-workflow-screens` |
   | `app/services/stages/run_provider.rb`, `app/services/ai_cli/{rotation,providers,provider,agent_setting}.rb`, or their listed specs | `ai-worker-cli-selection` |
   | `app/services/ai_cli/**`, `app/services/ci/**`, `app/services/stages/run_tooling.rb`, or their listed specs | `ai-worker-agent-cli` |
   | a new detached-agent fetch/sync/triage service/job; `AiCli::DetachedRun`; or `app/services/agent_runs/**` | `ai-worker-detached-agent-runs` |
   | `app/services/brainstorm/**`, `app/jobs/brainstorm_job.rb`, `project_brainstorms_controller.rb`, or their listed specs | `ai-worker-brainstorm` |
   | `app/models/bugsnag_sync.rb`, `app/services/bugsnag/**`, `app/jobs/bugsnag_sync_job.rb`, bugsnag_sync schedule entries, Bugsnag controllers/views, or their listed specs | `ai-worker-bugsnag-triage` |
   | `app/models/jira_sync.rb`, listed Jira ticket-sync services, `app/jobs/jira_sync_job.rb`, jira_sync schedule entries, Jira-sync controllers/views, or their specs | `ai-worker-jira-ticket-sync` |
   | listed Jira worklog/time-log services, `app/jobs/jira_hours_sync_job.rb`, `app/models/time_log.rb`, `WorkflowTimeLogsController`, or log-time project/workflow views | `ai-worker-jira-worklogs` |
   | listed Slack review-ping services, `app/jobs/slack_ping_job.rb`, slack_ping schedule entry, or their listed specs | `ai-worker-slack-review-pings` |
   | `app/services/scheduling/**`, `app/jobs/workflow_scheduler_job.rb`, `config/sidekiq.yml`, `config/schedule.yml`, or scheduler concurrency specs | `ai-worker-scheduling` |
   | a stage type, Workflow status, or agent result-marker change spanning Stage, StageRun::ACTIONS, Workflow, StageExecutor, prompts, AiCli::Output, and scheduler | `ai-worker-stage-types` |
   | `app/services/{git,github}/**`, or their specs | `ai-worker-git-github` |
   | prompt files owned by `ai-worker-prompts`: `app/services/prompts/{slack_post,conflict_resolution,stage_prompt,renderer,workflow_placeholders,project_placeholders,defaults,stage_sections}.rb`, `defaults/jira_update.md`, its listed section files, `prompt_template.rb`, or `docs/PROMPT_TEMPLATES.md` | `ai-worker-prompts` |
   | `app/services/stage_executor.rb`, or remaining generic `app/services/stages/**` and their specs | `ai-worker-stage-pipeline` |
   | remaining `app/models/{project,workflow,stage,stage_run,prompt_template}.rb`, `app/models/stages/run_history.rb`, listed domain workflow/project POROs, `db/migrate/**`, or `db/schema.rb` | `ai-worker-domain` |
   | remaining ProjectsController CRUD, prompt templates, settings and rotations, shared UI, remaining Stimulus controllers, or routes | `ai-worker-ui` |
   | `app/jobs/application_job.rb`, `config/initializers/sidekiq.rb`, shared subprocess/error conventions, or a new unowned service namespace/job | `ai-worker-orchestration` |
   | any `spec/**` not already matched above | `ai-worker-testing` |

   A diff that only extracts, splits or moves code also needs `ai-worker-refactoring`.
4. Apply the checklist to the diff. Output format: `<file>:<line> — <SEVERITY> — <message>`, then a summary line with BLOCKING/HIGH/MEDIUM/LOW counts.
5. Stop after reporting — this skill does not commit, push, or open a PR. Hand off to a `pr-create`-style skill for that, if one is available in this project.
