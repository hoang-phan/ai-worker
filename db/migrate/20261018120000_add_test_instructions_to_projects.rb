class AddTestInstructionsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :test_instructions, :text
  end
end
