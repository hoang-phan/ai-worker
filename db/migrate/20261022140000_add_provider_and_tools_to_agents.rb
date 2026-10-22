class AddProviderAndToolsToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :provider, :string
    add_column :agents, :allowed_tools, :json, null: false, default: []
    add_column :workflows, :ai_provider, :string
  end
end
