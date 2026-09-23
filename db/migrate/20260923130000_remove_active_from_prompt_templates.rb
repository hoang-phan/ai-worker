class RemoveActiveFromPromptTemplates < ActiveRecord::Migration[8.1]
  def change
    remove_column :prompt_templates, :active, :boolean, default: false, null: false
  end
end
