class AddBrainstormToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :brainstorm_enabled, :boolean, null: false, default: false
    add_column :projects, :brainstorm_auto_start, :boolean, null: false, default: false
    add_column :projects, :brainstorm_max_workflows, :integer, null: false, default: 5
    add_column :projects, :brainstorm_goal, :text
    add_column :projects, :brainstorm_last_run_at, :datetime
    add_column :projects, :brainstorm_last_result, :string
    add_column :workflows, :summary, :string
  end
end
