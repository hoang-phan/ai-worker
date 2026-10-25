module Jira
  # Syncs one Jira site's ticket keys into time_logs via TimeLogMirror. Per-ticket WorklogError failures are recorded
  # and leave that ticket's rows alone; missing credentials abort. Successful workflows get jira_logged_synced_at stamped.
  class WorklogSiteSync
    def initialize(client:, mirror: TimeLogMirror.new, clock: -> { Time.current })
      @client = client
      @mirror = mirror
      @clock = clock
    end

    def call(workflows, keys)
      result = HoursSync::Result.new(synced: 0, failed: [])
      workflow_by_key = workflows.select(&:jira_key).index_by(&:jira_key)
      failed_keys = keys.uniq.reject { |key| sync_ticket(key, workflow_by_key[key], result) }
      stamp_synced(workflows, failed_keys)
      result
    end

    private

    # Mirrors one ticket; returns true on success. A failure is recorded in the result and the ticket keeps its old rows,
    # except missing credentials, which abort the whole run.
    def sync_ticket(key, workflow, result)
      @mirror.replace(key, @client.my_worklogs(key), workflow: workflow)
      result.synced += 1
      true
    rescue WorklogError => e
      raise if e.missing_credentials?

      result.failed << "#{key}: #{e.message}"
      false
    end

    def stamp_synced(workflows, failed_keys)
      workflows.each do |workflow|
        next unless workflow.jira_key
        next if failed_keys.include?(workflow.jira_key)

        workflow.update_columns(jira_logged_synced_at: @clock.call)
      end
    end
  end
end
