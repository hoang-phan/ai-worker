class AddDefaultSkillsAndReviewersToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :default_skills, :text
    add_column :projects, :default_reviewers, :string
  end
end
