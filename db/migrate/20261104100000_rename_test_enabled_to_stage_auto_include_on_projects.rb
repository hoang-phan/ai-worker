# Credentials, not a checkbox, now make local/UAT testing available for a project. The old "enabled" flags keep their
# values under a new meaning: seed the optional test stage into every new workflow (instead of adding it by hand).
class RenameTestEnabledToStageAutoIncludeOnProjects < ActiveRecord::Migration[8.1]
  def change
    rename_column :projects, :uat_test_enabled, :uat_stage_auto_include
    rename_column :projects, :local_test_enabled, :local_stage_auto_include
  end
end
