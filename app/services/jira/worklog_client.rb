require "json"
require "net/http"

module Jira
  # Minimal Jira Cloud REST client: adds a worklog to an issue and reads an issue's logged total, authenticated with JIRA_EMAIL / JIRA_ACCESS_TOKEN.
  # Errors are mapped to Jira::WorklogError.
  class WorklogClient
    def initialize(base_url, email: ENV["JIRA_EMAIL"], token: ENV["JIRA_ACCESS_TOKEN"])
      @base_url = base_url.to_s.chomp("/")
      @email = email
      @token = token
    end

    # Returns the id of the created worklog.
    def add_worklog(ticket_key, started_at:, seconds:)
      raise WorklogError, "JIRA_EMAIL / JIRA_ACCESS_TOKEN are not set" if email.blank? || token.blank?

      uri = URI("#{base_url}/rest/api/3/issue/#{ticket_key}/worklog")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Accept" => "application/json")
      request.basic_auth(email, token)
      request.body = { started: started_at.strftime("%Y-%m-%dT%H:%M:%S.000%z"), timeSpentSeconds: seconds }.to_json
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      raise WorklogError, "Jira worklog for #{ticket_key} failed (HTTP #{response.code})" unless response.code.to_i == 201

      JSON.parse(response.body)["id"]
    rescue JSON::ParserError, SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError => e
      raise WorklogError, "Jira request failed: #{e.message}"
    end

    # Sets the ticket's original estimate to `seconds` when it is blank or 0 (not estimated); returns true if it was updated.
    def set_original_estimate_if_blank(ticket_key, seconds)
      raise WorklogError, "JIRA_EMAIL / JIRA_ACCESS_TOKEN are not set" if email.blank? || token.blank?

      current = get_json("/rest/api/3/issue/#{ticket_key}", fields: "timetracking").dig("fields", "timetracking", "originalEstimateSeconds").to_i
      return false if current.positive?

      uri = URI("#{base_url}/rest/api/3/issue/#{ticket_key}")
      request = Net::HTTP::Put.new(uri, "Content-Type" => "application/json", "Accept" => "application/json")
      request.basic_auth(email, token)
      request.body = { fields: { timetracking: { originalEstimate: "#{[ (seconds / 60.0).ceil, 1 ].max}m" } } }.to_json
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      raise WorklogError, "Jira estimate update for #{ticket_key} failed (HTTP #{response.code})" unless response.code.to_i == 204

      true
    rescue JSON::ParserError, SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError => e
      raise WorklogError, "Jira request failed: #{e.message}"
    end

    # The authenticated user's (JIRA_EMAIL account) worklogs on a ticket, paged like jira_hours_report.py:
    # [{ id:, started: Time, seconds: }]. Matched on accountId: Jira Cloud often hides author emails.
    def my_worklogs(ticket_key)
      mine = account_id
      worklogs = []
      start_at = 0
      loop do
        data = get_json("/rest/api/3/issue/#{ticket_key}/worklog", startAt: start_at, maxResults: 1000)
        logs = data["worklogs"] || []
        worklogs += logs.select { |log| log.dig("author", "accountId") == mine }
                        .map { |log| { id: log["id"].to_s, started: Time.zone.parse(log["started"]), seconds: log["timeSpentSeconds"].to_i } }
        start_at += logs.size
        break if logs.empty? || start_at >= data["total"].to_i
      end
      worklogs
    rescue JSON::ParserError, SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError => e
      raise WorklogError, "Jira request failed: #{e.message}"
    end

    # Keys of the tickets the authenticated user has logged time on since `date`, whether or not the app knows them.
    def keys_with_my_worklogs_since(date)
      raise WorklogError, "JIRA_EMAIL / JIRA_ACCESS_TOKEN are not set" if email.blank? || token.blank?

      keys = []
      page_token = nil
      loop do
        params = { jql: %(worklogAuthor = currentUser() AND worklogDate >= "#{date.strftime('%Y-%m-%d')}"), fields: "key", maxResults: 100 }
        params[:nextPageToken] = page_token if page_token
        data = get_json("/rest/api/3/search/jql", params)
        keys += (data["issues"] || []).map { |issue| issue["key"] }
        page_token = data["nextPageToken"]
        break if page_token.blank? || data["isLast"]
      end
      keys
    rescue JSON::ParserError, SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError => e
      raise WorklogError, "Jira request failed: #{e.message}"
    end

    private

    def account_id
      raise WorklogError, "JIRA_EMAIL / JIRA_ACCESS_TOKEN are not set" if email.blank? || token.blank?

      @account_id ||= get_json("/rest/api/3/myself", {}).fetch("accountId")
    end

    def get_json(path, params)
      uri = URI("#{base_url}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?
      request = Net::HTTP::Get.new(uri, "Accept" => "application/json")
      request.basic_auth(email, token)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      raise WorklogError, "Jira #{path[%r{issue/([^/]+)}, 1] || path} could not be read (HTTP #{response.code})" unless response.code.to_i == 200

      JSON.parse(response.body)
    end

    attr_reader :base_url, :email, :token
  end
end
