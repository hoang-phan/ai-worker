class AddPrSkills < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :default_pr_skills, :text
    add_column :workflows, :pr_skills, :text
  end
end
