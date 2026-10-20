require "json"
require "net/http"

module Slack
  # Minimal Slack Web API client: one authenticated chat.postMessage call, errors mapped to Slack::NotifyError.
  class WebClient
    API_URL = URI("https://slack.com/api/chat.postMessage")

    def initialize(token)
      @token = token
    end

    # Returns the parsed response body (includes the message's `ts`). Posts into `thread_ts` when given.
    def post_message(channel:, text:, thread_ts: nil)
      request = Net::HTTP::Post.new(API_URL, "Content-Type" => "application/json; charset=utf-8",
                                             "Authorization" => "Bearer #{token}")
      payload = { channel: channel, text: text, unfurl_links: false, unfurl_media: false }
      payload[:thread_ts] = thread_ts if thread_ts.present?
      request.body = payload.to_json
      response = Net::HTTP.start(API_URL.host, API_URL.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
      body = JSON.parse(response.body)
      raise NotifyError, "Slack chat.postMessage failed: #{body['error'] || response.code}" unless body["ok"]

      body
    rescue JSON::ParserError, SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError => e
      raise NotifyError, "Slack request failed: #{e.message}"
    end

    private

    attr_reader :token
  end
end
