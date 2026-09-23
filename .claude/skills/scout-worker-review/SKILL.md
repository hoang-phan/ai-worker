---
name: scout-worker-review
description: Pre-PR local review for scout-worker, covering subprocess safety, stage/enum invariants, and audit-log completeness. Use before opening a PR against this repo.
argument-hint: '[--base <ref>] [--staged | --working]'
---

# scout-worker-review

Reviews the diff against `main` (or `--staged` / `--working` if passed) using `git -C <repo> diff <args>` — never `cd <repo> && git diff`, for the same non-interactive-safety reason the app's own services avoid `cd &&` strings.

1. Get the diff: `git -C . diff main...HEAD` (or the requested range).
2. Load `assets/review-checklist.md` — the stable, rarely-changing review criteria for this app.
3. For each changed file, map it to the relevant narrow skill (`scout-worker-domain`, `scout-worker-orchestration`, `scout-worker-ui`) and re-read *that skill's* file map fresh, rather than assuming this review's own memory of the codebase is current.
4. Apply the checklist to the diff. Output format: `<file>:<line> — <SEVERITY> — <message>`, then a summary line with BLOCKING/HIGH/MEDIUM/LOW counts.
5. Stop after reporting — this skill does not commit, push, or open a PR. Hand off to a `pr-create`-style skill for that, if one is available in this project.
