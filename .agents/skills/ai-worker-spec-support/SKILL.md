---
name: ai-worker-spec-support
description: Owns shared ai-worker spec setup. Use when adding or changing spec/support helpers or shared examples, except helpers owned by another skill.
---

# ai-worker spec support

Owns `spec/support/**` except `spec/support/skill_path_helper.rb` (owned by `ai-worker-skills`) and `spec/support/ci_loop_helper.rb` (owned by `ai-worker-ci-loop`).

## File map

- `spec/support/active_job_test_adapter.rb` — `active_job_test_adapter: true` example metadata switches `ActiveJob::Base.queue_adapter` to `:test` and restores it; use for specs that assert enqueued jobs. Required lets: none.
- `spec/support/fake_cycle_source.rb` — `FakeCycleSource`, a recording `AgentRuns::CycleSource` with `calls`, `payload`, eligibility accessors, `failures`, and `rescue_errors`; use in `AgentRuns::SyncCycle` specs. Required lets: none.
- `spec/support/fake_detached_run.rb` — `FakeDetachedRun` records `start` kwargs and yields `rows` from `poll`; use as an injected detached run in fetcher specs. Required lets: none.
- `spec/support/git_repo_helper.rb` — `GitRepoHelper` provides `git`, `configure_git_user`, `commit_file`, `build_git_fixture`, and `build_other_clone`; use for throwaway bare-origin Git fixtures under a temporary directory. Required lets: none.
- `spec/support/projects_validator_helper.rb` — `ProjectsValidatorHelper` supplies `let_tmpdir(:local_directory, ...)`, `project(**attrs)`, and `errors_for`; include in `Projects::Validator` specs needing a local directory. Required lets: none.
- `spec/support/rails_cache.rb` — clears `Rails.cache` before each example; use automatically to prevent cache state leaking between examples. Required lets: none.
- `spec/support/record_helper.rb` — `RecordHelper` supplies project, workflow, stage, and running-AI-run builders plus `let_jira_project` and `let_personal_project`; use to create only the records an example needs. Required lets: none.
- `spec/support/stage_run_helper.rb` — `StageRunHelper#stage_actions(stage)` and `have_finished_ai_run` inspect stage-run order and reset AI-run state; use in workflow/stage-run assertions. Required lets: none.
- `spec/support/tmp_dir_helper.rb` — `let_tmpdir`, `make_tmpdir`, `register_tmpdir`, and `remove_tmpdirs` create and safely remove directories below `Dir.tmpdir`; use for filesystem-backed examples. Required lets: none.
- `spec/support/shared_examples/detached_fetcher.rb` — `it_behaves_like "a detached-run fetcher"` covers `running?` and `last_started_at` delegation; use for services wrapping a detached run. Required lets: `run`, `fetcher`.
- `spec/support/shared_examples/manual_start_action.rb` — `it_behaves_like "a manual start action"` covers blocked, started, already-running, and failed manual starts; use for request actions that start an agent run. Required lets: `perform_request`, `make_blocked`, `make_running`, `make_failing`, `blocked_alert`, `started_notice`, `running_alert`, `failed_alert`.
- `spec/support/shared_examples/project_child_crud.rb` — `it_behaves_like "project child CRUD"` covers project-nested new/edit/create/update/destroy and foreign-record 404 behavior; use for controllers built on `ProjectChildCrud`. Required lets: `project`, `model_class`, `param_key`, `flash_label`, `child_collection`, `record`, `other_record`, `foreign_record`, `new_path`, `create_path`, `edit_path`, `member_path`, `foreign_edit_path`, `valid_params`, `created_lookup`, `created_attributes`, `protected_params`, `protected_lookup`, `protected_expectations`, `update_params`, `updated_attributes`, `original_attributes`, `invalid_create_params`, `invalid_update_params`; optional: `invalid_setup`.
- `spec/support/shared_examples/sync_cycle_job.rb` — `it_behaves_like "an agent sync-cycle job"` covers eligible-record cycles and recoverable source failures; use for jobs that enumerate records and invoke `AgentRuns::SyncCycle`. Required lets: `source_class`, `eligible_records`, `ineligible_records`, `log_prefix_for`, `error_class`, `failure_observer`.

## Conventions

- `spec/rails_helper.rb` auto-requires every `spec/support/**/*.rb`; support helpers are available without manual requires.
- Shared examples belong in `spec/support/shared_examples/` and must never be named `*_spec.rb`, because the normal spec glob would run them twice.
- Do not put global stubs in support files. The global/constructor-stub ratchets scan `spec/support`; inject a collaborator or keep the stub local to the example instead.
- Prefer extending an existing helper or shared example over adding a new one. Add a new support file only when its setup is broadly reusable and does not fit an established helper.
