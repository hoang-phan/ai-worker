class AddAgentLessonsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :agent_lessons, :text
  end
end
