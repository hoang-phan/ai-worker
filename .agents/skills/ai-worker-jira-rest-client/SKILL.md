---
name: ai-worker-jira-rest-client
description: Owns ai-worker's focused Jira Cloud REST client contracts. Use for any task touching app/services/jira/{rest_client,http_transport,worklog_client,worklog_error}.rb or their mirrored specs.
---

# ai-worker Jira REST client

Owns the external Jira Cloud client only: transport, authentication, request/paging plumbing, worklog API calls, and `Jira::WorklogError`. It is separate from allocation, `TimeLog` persistence, hours/site synchronization, jobs, and time-log UI; those belong to `ai-worker-jira-worklogs`.

## Owned files

- `app/services/jira/rest_client.rb` and `spec/services/jira/rest_client_spec.rb` — `Jira::RestClient.new(base_url, email:, token:, transport:)`. Its injectable `transport:` seam serves `ensure_credentials!`, `get_json`, `request(method, path, params:, body:, expect:) { |code| message }`, `each_offset_page`, and `each_token_page`.
- `app/services/jira/http_transport.rb` and `spec/services/jira/http_transport_spec.rb` — `Jira::HttpTransport#call(request, uri)` is the real `Net::HTTP` round trip. It uses a five-second open timeout and 15-second read timeout.
- `app/services/jira/worklog_client.rb` and `spec/services/jira/worklog_client_spec.rb` — `Jira::WorklogClient.new(base_url, email:, token:, transport:, rest:)` composes the REST client and exposes the worklog-specific API.
- `app/services/jira/worklog_error.rb` and `spec/services/jira/worklog_error_spec.rb` — `Jira::WorklogError`, including the `:missing_credentials` reason and `#missing_credentials?` predicate.

## REST contracts

- Credentials are `JIRA_EMAIL` and `JIRA_ACCESS_TOKEN` by default. `ensure_credentials!` raises `Jira::WorklogError` with `reason: :missing_credentials` before a request when either is blank.
- Requests use the base URL (without a trailing slash), basic authentication, `Accept: application/json`, URL-encoded query parameters, and JSON bodies with `Content-Type: application/json` when a body is supplied. Expected-status mismatches use the caller's block to build the `WorklogError` message.
- JSON parse failures and transport failures (`SystemCallError`, `Timeout::Error`, `SocketError`, and `OpenSSL::SSL::SSLError`) map to `Jira::WorklogError`. Preserve this error type and its existing messages; do not introduce a generic client/error framework.
- Offset paging sends `startAt`, yields data and the configured item collection, and stops when that collection is empty or the advanced offset reaches `total`.
- Token paging sends `nextPageToken` after the first page and stops when the token is blank or `isLast` is truthy.

## Worklog API contracts

- `add_worklog(key, started_at:, seconds:)` POSTs the Jira worklog payload and returns the created worklog id.
- `set_original_estimate_if_blank(key, seconds)` reads `timetracking`; it leaves a positive existing original estimate alone, otherwise PUTs a whole-minute original estimate and returns whether it updated.
- `my_worklogs(key)` fetches `/myself` once per client instance and caches its `accountId`; it follows offset pages and returns only worklogs whose author `accountId` matches that cached value, as `{ id:, started:, seconds: }` hashes.
- `keys_with_my_worklogs_since(date)` searches JQL for `worklogAuthor = currentUser()` with the supplied date, asks only for `key`, follows token pages, and returns keys even when the app has no local workflow for them.

## Testing

- Never call Jira in specs. Supply a callable `transport:` to `RestClient`/`WorklogClient`, or a `rest:` double to `WorklogClient`; only `http_transport_spec` stubs `Net::HTTP.start`.
- Keep plumbing behavior (authentication, request construction, status/JSON/transport failures, and both pagination protocols) in `rest_client_spec`. Keep HTTP timeout coverage in `http_transport_spec`.
- Keep worklog paths/payloads, estimate behavior, cached-account filtering, and JQL key discovery in `worklog_client_spec`. Keep `WorklogError` reason/predicate behavior in `worklog_error_spec`.

Run the focused suite with `RAILS_ENV=test bundle exec rspec spec/services/jira/{rest_client,http_transport,worklog_client,worklog_error}_spec.rb`.
