class CreateBugsnagSyncs < ActiveRecord::Migration[8.1]
  def change
    create_table :bugsnag_syncs do |t|
      t.references :project, null: false, foreign_key: true
      t.string :bugsnag_project, null: false
      t.string :jira_project, null: false
      t.integer :min_events, null: false, default: 5
      t.integer :max_tickets, null: false, default: 3
      t.boolean :auto_sync, null: false, default: false
      t.json :ledger, null: false, default: {}
      t.datetime :last_synced_at
      t.string :last_result
      t.timestamps
    end
  end
end
