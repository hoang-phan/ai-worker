class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :description, null: false, default: ""
      t.text :instructions, null: false, default: ""
      t.string :model
      t.string :effort
      t.timestamps
    end
    add_index :agents, %i[project_id name], unique: true

    create_table :agent_delegations do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :delegate, null: false, foreign_key: { to_table: :agents }
      t.timestamps
    end
    add_index :agent_delegations, %i[agent_id delegate_id], unique: true

    add_reference :stages, :agent, foreign_key: { on_delete: :nullify }
  end
end
