---
name: ai-worker-spec-guards
description: Owns ai-worker's structural spec guards. Use for any task touching spec/structure/** or its EXEMPT and ALLOWLIST caps.
---

# ai-worker structural spec guards

## File map

- `spec/structure/spec_mirror_spec.rb` — requires focused mirrored specs for production models, services, jobs, and helpers.
- `spec/structure/constructor_stub_ratchet_spec.rb` — caps app-namespace constructor stubs in specs and support helpers.
- `spec/structure/global_stub_ratchet_spec.rb` — caps app-global method, constant, and any-instance stubs.
- `spec/structure/verified_double_ratchet_spec.rb` — caps plain `double("Some::Class")` fakes; prefer verifying doubles.
- `spec/structure/private_state_peek_ratchet_spec.rb` — caps private-state inspection and private-method calls.
- `spec/structure/file_length_ratchet_spec.rb` — caps line counts for Ruby production files, specs, and ERB views.
- `spec/structure/time_travel_ratchet_spec.rb` — caps wall-clock time-travel helpers in specs.
- `spec/structure/support/match_count_ratchet.rb` — shared plain-Ruby file scanning and match counting for structural ratchets.
- `spec/structure/request_spec_mirror_spec.rb` — requires mirrored request specs for controllers.

## Rules

- ALLOWLIST and EXEMPT caps are only ever lowered or deleted, never raised. Remove an entry when its guarded use or exempted file goes away.
- A new guard needs a commented EXEMPT or ALLOWLIST whose entries state their reasons. Include an accuracy example such as `it "keeps EXEMPT accurate" do` that removes entries when the source file disappears or gains its required mirror.
- Guards scan only `spec/**` and `app/**` through `Dir.glob`; they must not load Rails or `require "rails_helper"`. `require "spec_helper"` is permitted.
- Keep guards structural and text/file-system based: do not add application dependencies, fixtures, database access, or external calls.
- Define each guard's constants inside its per-guard module; do not define constants directly in an `RSpec.describe` block.

## Verification

- Run `RAILS_ENV=test bundle exec rspec spec/structure`.
