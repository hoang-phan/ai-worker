class SettingsController < ApplicationController
  include SettingsScreen

  def show
    load_settings
  end

  def update
    AiCli::AgentSetting.current = params[:agent]
    redirect_to settings_path, notice: "Agent set to #{AiCli::AgentSetting.current}."
  rescue ArgumentError => e
    render_settings_error(e)
  end
end
