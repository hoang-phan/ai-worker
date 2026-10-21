class AddFlowToProjectsAndCommandToStages < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :flow, :integer, default: 0, null: false
    add_column :stages, :command, :text
  end
end
