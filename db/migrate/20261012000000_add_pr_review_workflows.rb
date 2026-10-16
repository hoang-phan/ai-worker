class AddPrReviewWorkflows < ActiveRecord::Migration[8.1]
  def change
    change_table :workflows do |t|
      t.integer :kind, null: false, default: 0
      t.string :slack_url
    end

    change_table :projects do |t|
      t.boolean :slack_review_enabled, null: false, default: false
      t.string :slack_mention
      t.datetime :slack_last_synced_at
      t.string :slack_last_result
    end
  end
end
