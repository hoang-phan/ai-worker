class AddUatTesting < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :uat_test_enabled, :boolean, default: false, null: false
    add_column :projects, :uat_test_delay_minutes, :integer, default: 120, null: false
    add_column :projects, :uat_url, :string
    add_column :projects, :uat_username, :string
    add_column :projects, :uat_password, :text
    add_column :workflows, :uat_test_at, :datetime
  end
end
