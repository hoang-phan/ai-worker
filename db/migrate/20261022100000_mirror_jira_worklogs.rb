class MirrorJiraWorklogs < ActiveRecord::Migration[8.1]
  def change
    add_column :workflows, :jira_logged_synced_at, :datetime
    change_column_null :time_logs, :workflow_id, true
    add_index :time_logs, :ticket_key
    add_index :time_logs, :jira_worklog_id
  end
end
