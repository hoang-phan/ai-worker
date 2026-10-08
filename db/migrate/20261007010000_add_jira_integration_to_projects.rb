class AddJiraIntegrationToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :jira_base_url, :string
    add_column :projects, :jira_assignee, :string

    create_table :jira_syncs do |t|
      t.references :project, null: false, foreign_key: true
      t.string :board
      t.string :parent_ticket
      t.boolean :auto_sync, null: false, default: false
      t.datetime :last_synced_at
      t.string :last_result
      t.timestamps
    end
  end
end
