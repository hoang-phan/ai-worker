class CreatePromptTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_templates do |t|
      t.string :name, null: false
      t.integer :stage_type, null: false
      t.text :body, null: false
      t.boolean :active, null: false, default: false

      t.timestamps
    end
  end
end
