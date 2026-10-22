class AddRotationProviderToWorkflows < ActiveRecord::Migration[8.1]
  def change
    add_column :workflows, :rotation_provider, :string
  end
end
