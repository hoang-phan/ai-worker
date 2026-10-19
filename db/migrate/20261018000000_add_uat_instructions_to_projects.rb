class AddUatInstructionsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :uat_instructions, :text
  end
end
