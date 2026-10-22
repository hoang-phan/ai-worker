---
name: ai-worker-testing
description: Applies ai-worker's testing discipline. Use for any task that adds or changes specs, or touches spec/** — model, service, job and request specs, spec helpers, and stubbing of claude/gh/git subprocesses.
---

# ai-worker-testing

## Layout and running

- Specs live in `spec/{models,services,jobs,requests}`, mirroring `app/`. Helpers: `spec/rails_helper.rb`, `spec/spec_helper.rb`.
- Always run with the environment set explicitly: `RAILS_ENV=test bundle exec rspec` (or a single file/line). Never rely on the default environment — it is development, which is real data. Test DB is `storage/test.sqlite3`; prepare with `RAILS_ENV=test bin/rails db:test:prepare`.
- Transactional fixtures are on (`use_transactional_fixtures = true`); records created in an example roll back automatically.
- CI runs the same commands in the `test` job (`.github/workflows/ci.yml`) and in `config/ci.rb` (`bin/ci`).

## Data safety

- Never touch development data. No `destroy_all` / `delete_all` / truncate "clean slate" cleanup — rely on transactions, or delete only the exact records you created.
- For `Project#local_directory` use `Dir.mktmpdir` and remove only that dir in an `after` hook, guarded by `start_with?(Dir.tmpdir)` (see `spec/models/project_spec.rb`).

## No real external calls

- Never invoke real `claude`, `gh`, or `git` against the network. Stub `Open3.capture3`, `Process.spawn`, `AiCli::Runner.start` / `.poll`.
- Services that spawn agents (`AiCli::DetachedRun`, `Brainstorm::RunLifecycle`) take an injectable `runner:`; pass a fake/`instance_double` instead of stubbing `AiCli::Runner` globally (spec recipes for `spec/services/ai_cli/**` and `spec/services/ci/**`: `ai-worker-agent-cli`).
- Build records with `RecordHelper` (`build_jira_project`, `build_personal_project`, `build_jira_workflow(project, ...)`, `build_task_workflow(project, ...)`); pass only the attributes the spec cares about. `CiLoopHelper` builds on it.
- For `Git::BranchService`, use `GitRepoHelper`'s bare-origin fixtures (`build_git_fixture`, `build_other_clone`) under `Dir.mktmpdir`, and remove only that tmpdir afterwards.

## Design

- Prefer extracting pure logic into small POROs (e.g. `AiCli::Output`, `Prompts::StagePrompt`) and unit-testing them directly, over testing through jobs or subprocesses.
