class AddCiLoopToProjectsAndWorkflows < ActiveRecord::Migration[8.1]
  def change
    change_table :projects do |t|
      t.string :ci_command
      t.integer :ci_max_rounds, default: 5, null: false
      t.text :ci_verify_instructions
      t.text :pr_instructions
      t.boolean :pr_stage_enabled, default: false, null: false
    end

    change_table :workflows do |t|
      t.string :ci_output_path
      t.integer :ci_exit_status
    end
  end
end
