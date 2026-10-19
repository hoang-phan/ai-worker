class AddSlackReviewNotificationsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :slack_review_channel, :string
    add_column :projects, :slack_user_map, :text
  end
end
