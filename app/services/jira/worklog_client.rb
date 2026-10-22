module Jira
  # Jira worklog domain calls over Jira::RestClient: adds a worklog to an issue and reads an issue's logged total, authenticated with JIRA_EMAIL / JIRA_ACCESS_TOKEN.
  # Errors are mapped to Jira::WorklogError.
  class WorklogClient
    def initialize(base_url, email: ENV["JIRA_EMAIL"], token: ENV["JIRA_ACCESS_TOKEN"], transport: Jira::HttpTransport.new,
                   rest: Jira::RestClient.new(base_url, email: email, token: token, transport: transport))
      @rest = rest
    end

    # Returns the id of the created worklog.
    def add_worklog(ticket_key, started_at:, seconds:)
      ensure_credentials!
      body = { started: started_at.strftime("%Y-%m-%dT%H:%M:%S.000%z"), timeSpentSeconds: seconds }
      request(:post, "/rest/api/3/issue/#{ticket_key}/worklog", body: body, expect: 201) { |code| "Jira worklog for #{ticket_key} failed (HTTP #{code})" }["id"]
    end

    # Sets the ticket's original estimate to `seconds` when it is blank or 0 (not estimated); returns true if it was updated.
    def set_original_estimate_if_blank(ticket_key, seconds)
      ensure_credentials!
      current = get_json("/rest/api/3/issue/#{ticket_key}", fields: "timetracking").dig("fields", "timetracking", "originalEstimateSeconds").to_i
      return false if current.positive?

      body = { fields: { timetracking: { originalEstimate: "#{[ (seconds / 60.0).ceil, 1 ].max}m" } } }
      request(:put, "/rest/api/3/issue/#{ticket_key}", body: body, expect: 204) { |code| "Jira estimate update for #{ticket_key} failed (HTTP #{code})" }
      true
    end

    # The authenticated user's (JIRA_EMAIL account) worklogs on a ticket, paged like jira_hours_report.py:
    # [{ id:, started: Time, seconds: }]. Matched on accountId: Jira Cloud often hides author emails.
    def my_worklogs(ticket_key)
      ensure_credentials!
      mine = account_id
      worklogs = []
      each_offset_page("/rest/api/3/issue/#{ticket_key}/worklog", { maxResults: 1000 }) { |_data, logs| worklogs += my_worklogs_from(logs, mine) }
      worklogs
    end

    # Keys of the tickets the authenticated user has logged time on since `date`, whether or not the app knows them.
    def keys_with_my_worklogs_since(date)
      ensure_credentials!
      keys = []
      jql = %(worklogAuthor = currentUser() AND worklogDate >= "#{date.strftime('%Y-%m-%d')}")
      each_token_page("/rest/api/3/search/jql", { jql: jql, fields: "key", maxResults: 100 }) { |data| keys += issue_keys_from(data) }
      keys
    end

    private

    attr_reader :rest

    delegate :ensure_credentials!, :get_json, :request, :each_offset_page, :each_token_page, to: :rest

    def account_id
      @account_id ||= get_json("/rest/api/3/myself").fetch("accountId")
    end

    def my_worklogs_from(logs, account_id)
      logs.select { |log| log.dig("author", "accountId") == account_id }
          .map { |log| { id: log["id"].to_s, started: Time.zone.parse(log["started"]), seconds: log["timeSpentSeconds"].to_i } }
    end

    def issue_keys_from(data)
      (data["issues"] || []).map { |issue| issue["key"] }
    end
  end
end
