---
name: ai-worker-skills
description: Owns authoring and maintenance of ai-worker's own agent skills. Use for any task touching .agents/skills/**, spec/skills/**, or spec/support/skill_path_helper.rb.
---

# ai-worker skills

## Scope

Use this skill when adding, splitting, renaming, or editing a skill under `.agents/skills/**`, or when changing its skill-validation specs. `.claude/skills` is the symlinked mirror of `.agents/skills`; create and edit skills only in `.agents/skills`.

## File map

- `.agents/skills/*/SKILL.md` — skill frontmatter, file maps, conventions, verification, and cross-skill ownership pointers.
- `spec/skills/skill_references_spec.rb` — frontmatter, path-reference, and skill-name-reference checks.
- `spec/skills/description_length_spec.rb` — frontmatter description-length check.
- `spec/skills/symbol_references_spec.rb` — checks backticked class/instance method references against autoloaded application constants; document intentional gem or test-only exceptions in its commented allowlist.
- `spec/skills/file_map_coverage_spec.rb` — production-file coverage checks.
- `spec/skills/file_map_duplicates_spec.rb` — file-map ownership-bullet duplicate checks.
- `spec/skills/review_routing_spec.rb` — review-routing table coverage, uniqueness, ordering, and fallback checks.
- `spec/support/skill_path_helper.rb` — brace-glob expansion shared by skill specs.

## Conventions

- Every `SKILL.md` has YAML frontmatter whose `name` equals its directory name. Its `description` is at most 300 characters, one unquoted, single-line plain scalar that contains `Use ` and contains neither `: ` nor ` #`; do not start it with a quote, `>`, or `|`.
- Write file-map entries as `- \`path\` — description` using an em dash. `file_map_duplicates_spec.rb` parses that exact bullet form; each path may appear only once in one skill's map.
- Brace globs such as `app/services/ai_cli/command/{claude,codex}.rb` are expanded by `SkillPathHelper`; use them only for existing expanded paths.
- Reference every production file under `app/{models,services,controllers,helpers,jobs}`, plus production views, Stimulus controllers, default prompts, and stylesheets, from some skill as required by `file_map_coverage_spec.rb`.
- Every backticked path and every backticked `ai-worker-*` skill name must exist, as checked by `skill_references_spec.rb`.
- Give each file one owning skill. For work governed elsewhere, link with an `owned by X` pointer instead of duplicating its rules.
- Keep the routing table in `ai-worker-review` first-match-wins: give every skill except `ai-worker-review` exactly one row; mention `ai-worker-refactoring` outside the table; put narrower rows above fallbacks; and keep the `spec/**` to `ai-worker-testing` row last.

## Verification

- Run `RAILS_ENV=test bundle exec rspec spec/skills spec/structure`.
- When adding a skill, add its one `ai-worker-review` routing row above the final `spec/**` fallback.
