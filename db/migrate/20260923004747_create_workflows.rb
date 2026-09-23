class CreateWorkflows < ActiveRecord::Migration[8.1]
  def change
    create_table :workflows do |t|
      t.references :project, null: false, foreign_key: true
      t.string :jira_ticket
      t.string :branch_name
      t.string :github_pr_url
      t.string :github_reviewer
      t.text :skills
      t.integer :status, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.boolean :processing, null: false, default: false

      t.timestamps
    end
  end
end
