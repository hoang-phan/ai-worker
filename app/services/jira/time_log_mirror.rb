module Jira
  # Replaces one ticket's local time_logs with Jira's worklogs: rows whose worklog id is gone are deleted, the rest are
  # upserted by (ticket_key, jira_worklog_id). The workflow is attached only to rows that don't have one yet.
  class TimeLogMirror
    def replace(key, worklogs, workflow:)
      TimeLog.transaction do
        TimeLog.where(ticket_key: key).where.not(jira_worklog_id: worklogs.map { |w| w[:id] }).delete_all
        worklogs.each do |worklog|
          log = TimeLog.find_or_initialize_by(ticket_key: key, jira_worklog_id: worklog[:id])
          log.workflow ||= workflow
          log.update!(started_at: worklog[:started], seconds: worklog[:seconds])
        end
      end
    end
  end
end
