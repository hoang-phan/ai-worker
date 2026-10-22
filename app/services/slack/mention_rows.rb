module Slack
  # Pure: validates the parsed rows of the Slack fetch agent's mentions.json.
  #
  # Input: the Array DetachedRun yields (any elements). Output: an Array of { "slack_url", "pr_urls" } hashes with
  # stripped, de-duplicated PR URLs matching ReviewSync::PR_URL. Non-Hash rows and rows with a blank slack_url or
  # no valid PR URL are dropped.
  class MentionRows
    def self.call(rows)
      new(rows).call
    end

    def initialize(rows)
      @rows = rows
    end

    def call
      rows.filter_map do |row|
        next unless row.is_a?(Hash)

        slack_url = row["slack_url"].to_s.strip
        pr_urls = Array(row["pr_urls"]).map { |url| url.to_s.strip }.select { |url| url.match?(ReviewSync::PR_URL) }
        { "slack_url" => slack_url, "pr_urls" => pr_urls.uniq } if slack_url.present? && pr_urls.any?
      end
    end

    private

    attr_reader :rows
  end
end
