Prepare the {REGION} {PROJECT_NAME} release testing list. Read only; change nothing, post nothing.

1. With `gh`, fetch the latest DRAFT release of {REPO} whose tag ends in `.0` (not a hotfix):
   `gh release list -R {REPO} --limit 10` then `gh release view <tag> -R {REPO} --json body,tagName,isDraft`.
   If a draft cannot be viewed by tag, use `gh api repos/{REPO}/releases` and pick it from the JSON.
2. Take ONLY the items under the "## To be tested" heading (stop at the next "## " heading).
3. Remove an item if ANY of these is true:
   - it has no Jira ticket key like [UNS-1234] or [UIUX-1234] anywhere in the title (so "[NO-TICKET]" and untagged items go);
   - its title contains "NOT TESTABLE" (any case, with or without a space or hyphen);
   - it is about Cypress, specs, tests, RSpec or CI test infrastructure (e.g. "Cypress", "spec", "specs", "RSpec", "test:", "Frontend Specs", "Backend Specs");
   - it is devops/infrastructure (e.g. "terraform", "deploy", "CI", "docker", "pipeline", "Sidekiq worker config");
   - it was authored by a bot (author name contains "[bot]", e.g. dependabot).
   Keep everything else, in the original order. Do not reword titles.
4. Format every kept item as one Slack mrkdwn line, exactly:
   `• [KEY] title (<https://github.com/{REPO}/pull/NUMBER|#NUMBER>) <https://github.com/AUTHOR|@AUTHOR>`
   where NUMBER is the PR number in parentheses at the end of the line and AUTHOR the trailing @handle.
   Keep the "[KEY]" exactly as in the release (if the key is in the title as "(UNS-7618)", write "[UNS-7618]" first and drop the parenthesised key from the title).
5. Reply with a short summary (counts kept/removed per rule), then the list in this exact shape, nothing else after it:

VAR_BEGIN: RELEASE_ITEMS
<one kept line per item>
VAR_END
