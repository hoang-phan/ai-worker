class RemoveAgentFromWorkflows < ActiveRecord::Migration[8.1]
  def change
    remove_column :workflows, :agent, :integer, null: false, default: 0
  end
end
