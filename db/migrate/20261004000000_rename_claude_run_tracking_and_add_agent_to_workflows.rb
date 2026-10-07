class RenameClaudeRunTrackingAndAddAgentToWorkflows < ActiveRecord::Migration[8.1]
  def change
    rename_column :workflows, :claude_pid, :ai_pid
    rename_column :workflows, :claude_log_path, :ai_log_path
    rename_column :workflows, :claude_started_at, :ai_started_at
    rename_column :workflows, :claude_log_offset, :ai_log_offset
    add_column :workflows, :agent, :integer, null: false, default: 0
  end
end
