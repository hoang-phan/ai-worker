class AddMergedAndJiraUpdate < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :jira_tester, :string

    # Workflows finished before this feature existed have (presumably) had
    # their Jira tickets handled by hand; mark them `jira_updated` (6) so the
    # scheduler doesn't transition every historical ticket. Narrow on purpose:
    # only done (3) Jira-project development (0) workflows with a PR.
    execute <<~SQL
      UPDATE workflows SET status = 6
      WHERE status = 3 AND kind = 0 AND github_pr_url IS NOT NULL
        AND project_id IN (SELECT id FROM projects WHERE kind = 0)
    SQL
  end

  def down
    remove_column :projects, :jira_tester
  end
end
