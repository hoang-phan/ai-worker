class AddPromptToStages < ActiveRecord::Migration[8.1]
  def change
    add_column :stages, :prompt, :text
  end
end
