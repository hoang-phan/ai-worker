class CreateTimeLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :time_logs do |t|
      t.references :workflow, null: false, foreign_key: true
      t.string :ticket_key, null: false
      t.datetime :started_at, null: false
      t.integer :seconds, null: false
      t.string :jira_worklog_id
      t.timestamps
    end
    add_index :time_logs, :started_at
  end
end
