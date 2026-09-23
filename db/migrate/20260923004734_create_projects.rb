class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name
      t.string :local_directory
      t.string :repo_full_name

      t.timestamps
    end
  end
end
