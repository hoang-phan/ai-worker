require "json"
require "net/http"

module Jira
  # Minimal Jira Cloud REST client: adds a worklog to an issue and reads an issue's logged total, authenticated with JIRA_EMAIL / JIRA_ACCESS_TOKEN.
  # Errors are mapped to Jira::WorklogError.
  class WorklogClient
    def initialize(base_url, email: ENV["JIRA_EMAIL"], token: ENV["JIRA_ACCESS_TOKEN"], transport: Jira::HttpTransport.new)
      @base_url = base_url.to_s.chomp("/")
      @email = email
      @token = token
      @transport = transport
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
      each_offset_page("/rest/api/3/issue/#{ticket_key}/worklog", maxResults: 1000) { |_data, logs| worklogs += my_worklogs_from(logs, mine) }
      worklogs
    end

    # Keys of the tickets the authenticated user has logged time on since `date`, whether or not the app knows them.
    def keys_with_my_worklogs_since(date)
      ensure_credentials!
      keys = []
      jql = %(worklogAuthor = currentUser() AND worklogDate >= "#{date.strftime('%Y-%m-%d')}")
      each_token_page("/rest/api/3/search/jql", jql: jql, fields: "key", maxResults: 100) { |data| keys += issue_keys_from(data) }
      keys
    end

    private

    attr_reader :base_url, :email, :token, :transport

    def ensure_credentials!
      raise WorklogError.new("JIRA_EMAIL / JIRA_ACCESS_TOKEN are not set", reason: :missing_credentials) if email.blank? || token.blank?
    end

    def account_id
      @account_id ||= get_json("/rest/api/3/myself").fetch("accountId")
    end

    def get_json(path, params = {})
      request(:get, path, params: params, expect: 200) { |code| "Jira #{path[%r{issue/([^/]+)}, 1] || path} could not be read (HTTP #{code})" }
    end

    # Yields (data, items) for each startAt/total page of "worklogs" until a page is empty or startAt reaches total.
    def each_offset_page(path, params)
      start_at = 0
      loop do
        data = get_json(path, params.merge(startAt: start_at))
        items = data["worklogs"] || []
        yield data, items
        start_at += items.size
        break if items.empty? || start_at >= data["total"].to_i
      end
    end

    # Yields each nextPageToken page until the token is blank or the page is the last.
    def each_token_page(path, params)
      page_token = nil
      loop do
        page_params = page_token ? params.merge(nextPageToken: page_token) : params
        data = get_json(path, page_params)
        yield data
        page_token = data["nextPageToken"]
        break if page_token.blank? || data["isLast"]
      end
    end

    def my_worklogs_from(logs, account_id)
      logs.select { |log| log.dig("author", "accountId") == account_id }
          .map { |log| { id: log["id"].to_s, started: Time.zone.parse(log["started"]), seconds: log["timeSpentSeconds"].to_i } }
    end

    def issue_keys_from(data)
      (data["issues"] || []).map { |issue| issue["key"] }
    end

    # Build -> send -> check the status (the block builds the failure message from the code) -> parse JSON,
    # mapping transport errors to WorklogError.
    def request(method, path, params: {}, body: nil, expect:)
      uri = uri_for(path, params)
      response = transport.call(build_request(method, uri, body), uri)
      raise WorklogError, yield(response.code) unless response.code.to_i == expect

      parse_body(response)
    rescue JSON::ParserError, SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError => e
      raise WorklogError, "Jira request failed: #{e.message}"
    end

    def uri_for(path, params)
      URI("#{base_url}#{path}").tap { |uri| uri.query = URI.encode_www_form(params) if params.any? }
    end

    def build_request(method, uri, body)
      headers = { "Accept" => "application/json" }
      headers["Content-Type"] = "application/json" if body
      Net::HTTP.const_get(method.to_s.capitalize).new(uri, headers).tap do |req|
        req.basic_auth(email, token)
        req.body = body.to_json if body
      end
    end

    def parse_body(response)
      response.body.present? ? JSON.parse(response.body) : nil
    end
  end
end
