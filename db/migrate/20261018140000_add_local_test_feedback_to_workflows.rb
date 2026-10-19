class AddLocalTestFeedbackToWorkflows < ActiveRecord::Migration[8.1]
  def change
    add_column :workflows, :local_test_feedback, :text
  end
end
