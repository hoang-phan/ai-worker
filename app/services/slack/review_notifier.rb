require "json"
require "net/http"

module Slack
  class NotifyError < StandardError; end

  # Posts a one-line "please review" message to the project's Slack channel once a PR is up for review,
  # tagging the Slack users that map to the PR's GitHub reviewers (Project#slack_user_map). Optional:
  # needs a channel on the project and SLACK_BOT_TOKEN (a bot with chat:write that is in the channel).
  # Unlike Slack::MentionFetcher this talks to the Web API directly — one cheap HTTP call, no agent run.
  class ReviewNotifier
    API_URL = URI("https://slack.com/api/chat.postMessage")

    def self.token
      ENV["SLACK_BOT_TOKEN"].presence
    end

    def initialize(project)
      @project = project
    end

    def enabled?
      project.slack_review_channel.present? && self.class.token.present?
    end

    # Why notifications can't be sent right now, for the UI.
    def blockers
      list = []
      list << "Slack channel is not set" if project.slack_review_channel.blank?
      list << "SLACK_BOT_TOKEN is not set" if self.class.token.blank?
      list
    end

    # e.g. ":eyes: <@U1> <@U2> please review <https://github.com/o/r/pull/1|ENG-1 Fix thing>"
    # `again` marks a re-request after changes were pushed; `fixed` (what the changes address) is added to it.
    def message(pr_url:, label:, reviewers:, again: false, fixed: nil)
      tags = reviewers.map { |login| project.slack_user_id_for(login)&.then { |id| "<@#{id}>" } || "@#{login}" }
      link = "<#{pr_url}|#{escape(label)}>"
      return [ ":eyes:", *tags, "please review", link ].join(" ") unless again

      lines = [ [ ":eyes:", *tags, "changes pushed, please re-review", link ].join(" ") ]
      lines << "Fixed:\n#{escape(fixed).strip}" if fixed.present?
      lines.join("\n")
    end

    # Posts into `thread_ts` when given (a re-request replies in the original thread), otherwise as a new channel
    # message. Returns the message's own `ts`, which is the thread id for later replies.
    def notify!(pr_url:, label:, reviewers:, again: false, fixed: nil, thread_ts: nil)
      raise NotifyError, blockers.join("; ") unless enabled?

      post(message(pr_url: pr_url, label: label, reviewers: reviewers, again: again, fixed: fixed), thread_ts: thread_ts)["ts"]
    end

    private

    attr_reader :project

    def escape(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("|", "¦")
    end

    def post(text, thread_ts: nil)
      request = Net::HTTP::Post.new(API_URL, "Content-Type" => "application/json; charset=utf-8",
                                             "Authorization" => "Bearer #{self.class.token}")
      payload = { channel: project.slack_review_channel, text: text, unfurl_links: false, unfurl_media: false }
      payload[:thread_ts] = thread_ts if thread_ts.present?
      request.body = payload.to_json
      response = Net::HTTP.start(API_URL.host, API_URL.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
      body = JSON.parse(response.body)
      raise NotifyError, "Slack chat.postMessage failed: #{body['error'] || response.code}" unless body["ok"]

      body
    rescue JSON::ParserError, SystemCallError, Timeout::Error, SocketError, OpenSSL::SSL::SSLError => e
      raise NotifyError, "Slack request failed: #{e.message}"
    end
  end
end
