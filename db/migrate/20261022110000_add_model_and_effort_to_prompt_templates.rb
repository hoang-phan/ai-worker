class AddModelAndEffortToPromptTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :prompt_templates, :model, :string
    add_column :prompt_templates, :effort, :string
  end
end
