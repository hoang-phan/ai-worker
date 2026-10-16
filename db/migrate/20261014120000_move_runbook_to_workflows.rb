# Runbook stages belong to a workflow (one deployment), not to the project: a project is deployed many times.
# Data: `runbook` projects become `personal` ones (they only ever had a local directory); any stage definitions
# a project still has are kept as one pending runbook workflow that new runs can copy their stages from.
class MoveRunbookToWorkflows < ActiveRecord::Migration[8.1]
  def up
    now = Time.current.utc.to_fs(:db)
    select_rows("SELECT DISTINCT project_id FROM stage_definitions").flatten.each do |project_id|
      position = select_value("SELECT COALESCE(MAX(position), 0) + 1 FROM workflows WHERE project_id = #{project_id.to_i}")
      variables = select_value("SELECT variable_defaults FROM projects WHERE id = #{project_id.to_i}")
      execute(<<~SQL.squish)
        INSERT INTO workflows (project_id, kind, status, position, variables, awaiting_next, created_at, updated_at)
        VALUES (#{project_id.to_i}, 2, 0, #{position.to_i}, #{variables.nil? ? 'NULL' : connection.quote(variables)}, 0, '#{now}', '#{now}')
      SQL
      workflow_id = select_value("SELECT last_insert_rowid()")
      execute(<<~SQL.squish)
        INSERT INTO stages (workflow_id, stage_type, name, position, run_mode, channel, prompt, created_at, updated_at)
        SELECT #{workflow_id.to_i}, 5, name, position, run_mode, channel, prompt, '#{now}', '#{now}'
        FROM stage_definitions WHERE project_id = #{project_id.to_i}
      SQL
    end

    execute("UPDATE projects SET kind = 1 WHERE kind = 2")
    drop_table :stage_definitions
    remove_column :projects, :variable_defaults
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
