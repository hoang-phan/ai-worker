class AddClaudeRunTrackingToWorkflows < ActiveRecord::Migration[8.1]
  def change
    add_column :workflows, :claude_pid, :integer
    add_column :workflows, :claude_log_path, :string
    add_column :workflows, :claude_started_at, :datetime
    add_column :workflows, :claude_log_offset, :integer, null: false, default: 0
  end
end
