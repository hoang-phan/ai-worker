module Bugsnag
  # Pure: merges triaged rows into a sync's ledger ({ bugsnag_id => jira_key }).
  #
  # Returns [new_ledger, added_keys]. Ids already in the ledger (or repeated in rows) keep their first key and
  # add nothing; the given ledger is not modified.
  class LedgerMerge
    def self.call(ledger, rows)
      new(ledger, rows).call
    end

    def initialize(ledger, rows)
      @ledger = ledger
      @rows = rows
    end

    def call
      merged = ledger.dup
      added = rows.filter_map do |row|
        next if merged.key?(row["bugsnag_id"])

        merged[row["bugsnag_id"]] = row["jira_key"]
        row["jira_key"]
      end
      [merged, added]
    end

    private

    attr_reader :ledger, :rows
  end
end
