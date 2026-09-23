class RemovePositionAndStatusFromStages < ActiveRecord::Migration[8.1]
  def change
    remove_column :stages, :position, :integer, default: 0, null: false
    remove_column :stages, :status, :integer, default: 0, null: false
  end
end
