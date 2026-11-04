# A stage's expected negative branch: where the workflow goes when the stage ends "failed" (reviewer requested changes,
# checks failing), as opposed to an error, which retries the same stage. Null means the stage type's default target
# (Workflows::StageFlow::DEFAULT_FAILURE_TYPE).
class AddFailureStageToStages < ActiveRecord::Migration[8.1]
  def change
    add_column :stages, :failure_stage_id, :integer
    add_index :stages, :failure_stage_id
  end
end
