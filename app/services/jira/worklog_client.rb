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

    # Total seconds logged in Jira on the ticket by everyone (sum of its worklogs, paged like jira_hours_report.py).
    def logged_seconds(ticket_key)
      raise WorklogError, "JIRA_EMAIL / JIRA_ACCESS_TOKEN are not set" if email.blank? || token.blank?

      total = 0
      start_at = 0
      loop do
        data = get_json("/rest/api/3/issue/#{ticket_key}/worklog", startAt: start_at, maxResults: 1000)
        logs = data["worklogs"] || []
        total += logs.sum { |log| log["timeSpentSeconds"].to_i }
        start_at += logs.size
        break if logs.empty? || start_at >= data["total"].to_i
      end
      total
    rescue JSON::ParserError, SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError => e
      raise WorklogError, "Jira request failed: #{e.message}"
    end

    private

    def get_json(path, params)
      uri = URI("#{base_url}#{path}")
      uri.query = URI.encode_www_form(params)
      request = Net::HTTP::Get.new(uri, "Accept" => "application/json")
      request.basic_auth(email, token)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      raise WorklogError, "Jira worklogs for #{path[%r{issue/([^/]+)}, 1]} could not be read (HTTP #{response.code})" unless response.code.to_i == 200

      JSON.parse(response.body)
    end

    attr_reader :base_url, :email, :token
  end
end
