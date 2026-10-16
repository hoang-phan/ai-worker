# Additive only: new columns and one new table, no data is touched.
class AddRunbookProjects < ActiveRecord::Migration[8.1]
  def change
    # Project-level placeholder defaults ({"VERSION" => "", "ENV" => "prod"}); the keys are the
    # variables a runbook workflow asks for, the values their defaults.
    add_column :projects, :variable_defaults, :json

    create_table :stage_definitions do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.integer :run_mode, null: false, default: 0
      t.string :channel
      t.text :prompt
      t.timestamps
    end

    add_column :stages, :name, :string
    add_column :stages, :position, :integer
    add_column :stages, :run_mode, :integer, null: false, default: 0
    add_column :stages, :channel, :string

    add_column :workflows, :variables, :json
    add_column :workflows, :current_stage_id, :integer
    add_column :workflows, :awaiting_next, :boolean, null: false, default: false
  end
end
