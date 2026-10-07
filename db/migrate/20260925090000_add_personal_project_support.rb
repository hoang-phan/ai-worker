class AddPersonalProjectSupport < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :kind, :integer, null: false, default: 0
    add_column :workflows, :task_description, :text
  end
end
