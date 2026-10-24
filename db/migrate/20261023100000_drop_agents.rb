# Project agents and their delegation links are gone; subagents are set up in the project's own folder instead.
class DropAgents < ActiveRecord::Migration[8.1]
  def change
    remove_reference :stages, :agent, foreign_key: { on_delete: :nullify }, index: true

    drop_table :agent_delegations do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :delegate, null: false, foreign_key: { to_table: :agents }
      t.timestamps
      t.index %i[agent_id delegate_id], unique: true
    end

    drop_table :agents do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :description, null: false, default: ""
      t.text :instructions, null: false, default: ""
      t.string :model
      t.string :effort
      t.string :provider
      t.json :allowed_tools, null: false, default: []
      t.timestamps
      t.index %i[project_id name], unique: true
    end
  end
end
