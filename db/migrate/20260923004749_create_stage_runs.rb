class CreateStageRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :stage_runs do |t|
      t.references :stage, null: false, foreign_key: true
      t.string :action
      t.text :output
      t.text :error

      t.timestamps
    end
  end
end
