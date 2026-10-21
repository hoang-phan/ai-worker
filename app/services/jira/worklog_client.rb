require "json"
require "net/http"

module Jira
  # Minimal Jira Cloud REST client: adds one worklog to an issue, authenticated with JIRA_EMAIL / JIRA_ACCESS_TOKEN.
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

    private

    attr_reader :base_url, :email, :token
  end
end
