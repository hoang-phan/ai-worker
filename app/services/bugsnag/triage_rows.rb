module Bugsnag
  # Pure: validates the parsed rows of the triage agent's result.json.
  #
  # Input: the Array DetachedRun yields (any elements). Output: an Array of { "bugsnag_id", "jira_key" } string
  # hashes, both stripped. Non-Hash rows and rows whose id or key doesn't match ID/KEY are dropped.
  class TriageRows
    ID = /\A[\w-]{6,64}\z/
    KEY = /\A[A-Z][A-Z0-9]+-\d+\z/

    def self.call(rows)
      new(rows).call
    end

    def initialize(rows)
      @rows = rows
    end

    def call
      rows.filter_map do |row|
        next unless row.is_a?(Hash)

        id = row["bugsnag_id"].to_s.strip
        key = row["jira_key"].to_s.strip
        { "bugsnag_id" => id, "jira_key" => key } if id.match?(ID) && key.match?(KEY)
      end
    end

    private

    attr_reader :rows
  end
end
