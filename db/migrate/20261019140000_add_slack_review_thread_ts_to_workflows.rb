class AddSlackReviewThreadTsToWorkflows < ActiveRecord::Migration[8.1]
  def change
    add_column :workflows, :slack_review_thread_ts, :string
  end
end
