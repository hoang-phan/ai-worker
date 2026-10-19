class AddCiInstructionsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :ci_instructions, :text
  end
end
