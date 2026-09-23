class CreateStages < ActiveRecord::Migration[8.1]
  def change
    create_table :stages do |t|
      t.references :workflow, null: false, foreign_key: true
      t.integer :stage_type, null: false
      t.integer :status, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.references :prompt_template, null: true, foreign_key: true

      t.timestamps
    end
  end
end
