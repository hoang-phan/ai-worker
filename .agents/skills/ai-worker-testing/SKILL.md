---
name: ai-worker-testing
description: Applies ai-worker's testing discipline. Use for any task that adds or changes specs, or touches spec/** — model, service, job and request specs, spec helpers, and stubbing of claude/gh/git subprocesses.
---

# ai-worker-testing

## Layout and running

- Specs live in `spec/{models,services,jobs,requests}`, mirroring `app/`. Helpers: `spec/rails_helper.rb`, `spec/spec_helper.rb`.
- New classes under `app/{models,services,jobs,helpers}` need a mirrored `spec/<same path>_spec.rb`; `spec/structure/spec_mirror_spec.rb` enforces this (controllers out of scope; only add to its EXEMPT list when a focused unit spec is not useful — error-only / Rails base / abstract base covered elsewhere).
- Always run with the environment set explicitly: `RAILS_ENV=test bundle exec rspec` (or a single file/line). Never rely on the default environment — it is development, which is real data. Test DB is `storage/test.sqlite3`; prepare with `RAILS_ENV=test bin/rails db:test:prepare`.
- Transactional fixtures are on (`use_transactional_fixtures = true`); records created in an example roll back automatically.
- Request specs use `let_tmpdir` + `RecordHelper` (`build_jira_project`, `build_personal_project`, `build_jira_workflow`, `build_task_workflow`, `build_runbook_workflow`, `build_pr_review_workflow`, `build_stage`, `build_runbook_stage`); tag a describe with `active_job_test_adapter: true` (`spec/support/active_job_test_adapter.rb`) to swap ActiveJob's queue adapter to `:test` for its examples instead of copying an `around` block.
- Request-spec shared examples live in `spec/support/shared_examples/` (auto-required; never name them `*_spec.rb`): `it_behaves_like "project child CRUD"` (`project_child_crud.rb`) covers new/edit/create/update/destroy/404 for a new project-nested controller built on `ProjectChildCrud`, and `it_behaves_like "a manual start action"` (`manual_start_action.rb`) covers blocked / started / already-running / failed-start flashes for a new "run now" action. Supply the `let`s documented at the top of each file and keep record- or action-specific examples in the including spec.
- CI runs the same commands in the `test` job (`.github/workflows/ci.yml`) and in `config/ci.rb` (`bin/ci`).

## Data safety

- Never touch development data. No `destroy_all` / `delete_all` / truncate "clean slate" cleanup — rely on transactions, or delete only the exact records you created.
- Specs get `tmp/test_state` automatically via `config.x.state_root` / `AgentRuns::StateRoot`; never point ROOT defaults or hand-built paths at `tmp/<subdir>` directly.
- For `Project#local_directory` use `let_tmpdir(:local_directory, "my-spec")` (or `make_tmpdir(prefix)` for several dirs) from `spec/support/tmp_dir_helper.rb`; it removes only paths under `Dir.tmpdir` that still exist after the example. Do not hand-roll `Dir.mktmpdir` + `after` cleanup.

## No real external calls

- Never invoke real `claude`, `gh`, or `git` against the network. Stub `Open3.capture3`, `Process.spawn`, `AiCli::Runner.start` / `.poll`.
- Services that spawn agents (`AiCli::DetachedRun`, `Brainstorm::RunLifecycle`) take an injectable `runner:`; pass a fake/`instance_double` instead of stubbing `AiCli::Runner` globally (spec recipes for `spec/services/ai_cli/**` and `spec/services/ci/**`: `ai-worker-agent-cli`).
- Services built on `AiCli::DetachedRun` (`Jira::AgentFetcher`, `Slack::MentionFetcher`, `Bugsnag::Triager`): use `let(:run) { FakeDetachedRun.new }` (`spec/support/fake_detached_run.rb`; records `start` kwargs, yields `rows` to `poll`) and `it_behaves_like "a detached-run fetcher"` (`spec/support/shared_examples/detached_fetcher.rb`; needs `run` and `fetcher` lets) for the `running?`/`last_started_at` delegation.
- Build records with `RecordHelper` (`build_jira_project`, `build_personal_project`, `build_jira_workflow(project, ...)`, `build_task_workflow(project, ...)`, `build_runbook_workflow(project, ...)`, `build_pr_review_workflow(project, ...)` (Jira project only), `build_stage(workflow, stage_type, ...)`, `build_runbook_stage(workflow, ...)`, `running_ai_run`); pass only the attributes the spec cares about. For the common project plus temporary directory setup, use `let_jira_project(prefix, **attrs)` or `let_personal_project(prefix, **attrs)`. `CiLoopHelper` builds on it. Use `StageRunHelper`'s `stage_actions(stage)` for oldest-first run actions and `have_finished_ai_run` for the `Workflow::AI_RUN_RESET` state when the provider is reset.
- For `Git::BranchService`, use `GitRepoHelper`'s bare-origin fixtures (`build_git_fixture`, `build_other_clone`) under a `let_tmpdir`/`make_tmpdir` directory.

## Design

- Prefer extracting pure logic into small POROs (e.g. `AiCli::Output`, `Prompts::StagePrompt`) and unit-testing them directly, over testing through jobs or subprocesses. For behaviour-preserving extractions, splits, slimming, or moves, follow `ai-worker-refactoring`.

## Seams over global stubs

- Inject collaborators by keyword (see `ai-worker-refactoring`) instead of `allow(X).to receive(:new)`.
- Thin cron jobs take a perform-keyword seam with a production default (`sync:`, `collector:`, `tick:`) so specs call `perform_now(sync: double)` (etc.) instead of stubbing `.new`.
- Inject a `clock:` callable instead of `freeze_time`/`travel_to` where the class offers one (`AiCli::DetachedRun`, `AiCli::StaleRun`, `Slack::ReviewNotifier`, `Jira::WorklogSiteSync`).
- `spec/structure/constructor_stub_ratchet_spec.rb` caps remaining `receive(:new)` stubs per file; lower or delete ALLOWLIST entries when you remove stubs (never raise caps).

