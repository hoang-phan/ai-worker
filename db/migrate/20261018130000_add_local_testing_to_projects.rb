class AddLocalTestingToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :local_test_enabled, :boolean, default: false, null: false
    add_column :projects, :local_url, :string
    add_column :projects, :local_instructions, :text
    add_column :projects, :local_username, :string
    add_column :projects, :local_password, :text
  end
end
