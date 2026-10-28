---
name: ai-worker-testing
description: Applies ai-worker's testing discipline. Use for any task that adds or changes specs, or touches spec/** — model, service, job and request specs, and stubbing of claude/gh/git subprocesses.
---

# ai-worker-testing

## Layout and running

- Specs live in `spec/{models,services,jobs,requests}`, mirroring `app/`. Helpers: `spec/rails_helper.rb`, `spec/spec_helper.rb`.
- Mirrored-spec requirements and structural guard exemptions are owned by `ai-worker-spec-guards`.
- Always run with the environment set explicitly: `RAILS_ENV=test bundle exec rspec` (or a single file/line). Never rely on the default environment — it is development, which is real data. Test DB is `storage/test.sqlite3`; prepare with `RAILS_ENV=test bin/rails db:test:prepare`.
- Transactional fixtures are on (`use_transactional_fixtures = true`); records created in an example roll back automatically.
- Test cache is `:memory_store` (`config/environments/test.rb`). Exercise `AiCli::AgentSetting` and `AiCli::Rotation` through their public API — do not stub `Rails.cache` or those singletons.
- Shared support helpers, builders, metadata, and shared examples are owned by `ai-worker-spec-support`.
- CI runs the same commands in the `test` job (`.github/workflows/ci.yml`) and in `config/ci.rb` (`bin/ci`).

## Data safety

- Never touch development data. No `destroy_all` / `delete_all` / truncate "clean slate" cleanup — rely on transactions, or delete only the exact records you created.
- Specs get `tmp/test_state` automatically via `config.x.state_root` / `AgentRuns::StateRoot`; never point ROOT defaults or hand-built paths at `tmp/<subdir>` directly.

## No real external calls

- Never invoke real `claude`, `gh`, or `git` against the network. Stub `Open3.capture3`, `Process.spawn`, `AiCli::Runner.start` / `.poll`.
- Services that spawn agents (`AiCli::DetachedRun`, `Brainstorm::RunLifecycle`) take an injectable `runner:`; pass a fake/`instance_double` instead of stubbing `AiCli::Runner` globally (spec recipes for `spec/services/ai_cli/**` and `spec/services/ci/**`: `ai-worker-agent-cli`).

## Design

- Prefer extracting pure logic into small POROs (e.g. `AiCli::Output`, `Prompts::StagePrompt`) and unit-testing them directly, over testing through jobs or subprocesses. For behaviour-preserving extractions, splits, slimming, or moves, follow `ai-worker-refactoring`.
- Define spec-only constants/classes via `let`/locals or a per-file module, never inside a describe block (enforced by `Lint/ConstantDefinitionInBlock`).

## Seams over global stubs

- Fake real collaborators with `instance_double`/`class_double`, never a plain `double` named after a class.
- Inject collaborators by keyword (see `ai-worker-refactoring`) instead of `allow(X).to receive(:new)`.
- Thin cron jobs take a perform-keyword seam with a production default (`sync:`, `collector:`, `tick:`, `cycle:`) so specs call `perform_now(sync: double)` (etc.) instead of stubbing `.new` or `AgentRuns::SyncCycle.call`.
- Inject a `clock:` callable instead of `freeze_time`/`travel_to` where the class offers one (`AiCli::DetachedRun`, `AiCli::StaleRun`, `Brainstorm::CycleSource`, `Slack::PingCollector`, `Slack::ReviewNotifier`, `Jira::WorklogSiteSync`).
- Inject a `logger:` keyword (default `Rails.logger`) instead of stubbing `Rails.logger` — used by `AiCli::LogTail`, `Slack::PingCollector`, `JiraHoursSyncJob`, and the sync-cycle jobs (`JiraSyncJob`, `SlackReviewJob`, `BugsnagSyncJob`, `BrainstormJob`) which forward it to `AgentRuns::SyncCycle`. Assert on `ActiveSupport::Logger.new(io = StringIO.new)` via `io.string`.
- Structural ratchets and their ALLOWLIST rules are owned by `ai-worker-spec-guards`.

