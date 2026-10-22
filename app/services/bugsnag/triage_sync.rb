module Bugsnag
  # Sync side of the Bugsnag triage: the readiness blockers and merging a
  # finished agent run's rows into the sync's ledger. The detached agent run
  # itself lives in Triager (exposed here as `triager`).
  class TriageSync
    Result = Struct.new(:added, keyword_init: true) do
      # Human summary of the newly added keys (shown as last_result).
      def summary
        added.any? ? "#{added.size} new ticket(s): #{added.join(', ')}" : "nothing new"
      end
    end

    def initialize(bugsnag_sync, triager: nil)
      @sync = bugsnag_sync
      @project = bugsnag_sync.project
      @triager = triager
    end

    def blockers
      Projects::RunBlockers.new(project).messages(:jira_kind, :jira_site_url, :local_directory)
    end

    def triager
      @triager ||= Triager.new(sync)
    end

    # `rows` is the array Triager#poll returns; merges it into the ledger.
    def import(rows)
      ledger, added = LedgerMerge.call(sync.ledger, rows)
      sync.update!(ledger: ledger)
      Result.new(added: added)
    end

    private

    attr_reader :sync, :project
  end
end
