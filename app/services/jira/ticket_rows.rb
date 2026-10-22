module Jira
  # Pure: validates the parsed rows of the Jira fetch agent's tickets.json.
  #
  # Input: the Array DetachedRun yields (any elements). Output: an Array of { "key", "summary" } string hashes.
  # Non-Hash rows and rows whose stripped key doesn't match KEY are dropped; a missing summary becomes "".
  class TicketRows
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

        key = row["key"].to_s.strip
        { "key" => key, "summary" => row["summary"].to_s } if key.match?(KEY)
      end
    end

    private

    attr_reader :rows
  end
end
