class RenameJiraSyncsBoardToJiraProject < ActiveRecord::Migration[8.1]
  def change
    rename_column :jira_syncs, :board, :jira_project
  end
end
