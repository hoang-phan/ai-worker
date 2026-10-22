require "json"
require "net/http"

module Jira
  # Generic Jira Cloud REST plumbing: basic-auth requests, JSON parsing, startAt/total and nextPageToken paging.
  # Errors are mapped to Jira::WorklogError.
  class RestClient
    def initialize(base_url, email:, token:, transport: Jira::HttpTransport.new)
      @base_url = base_url.to_s.chomp("/")
      @email = email
      @token = token
      @transport = transport
    end

    def ensure_credentials!
      raise WorklogError.new("JIRA_EMAIL / JIRA_ACCESS_TOKEN are not set", reason: :missing_credentials) if email.blank? || token.blank?
    end

    def get_json(path, params = {})
      request(:get, path, params: params, expect: 200) { |code| "Jira #{path[%r{issue/([^/]+)}, 1] || path} could not be read (HTTP #{code})" }
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

    # Yields (data, items) for each startAt/total page until a page is empty or startAt reaches total.
    def each_offset_page(path, params, items_key: "worklogs")
      start_at = 0
      loop do
        data = get_json(path, params.merge(startAt: start_at))
        items = data[items_key] || []
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

    private

    attr_reader :base_url, :email, :token, :transport

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
