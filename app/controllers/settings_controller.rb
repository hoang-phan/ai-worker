class SettingsController < ApplicationController
  def show
    load_settings
  end

  def update
    AiCli::AgentSetting.current = params[:agent]
    redirect_to settings_path, notice: "Agent set to #{AiCli::AgentSetting.current}."
  rescue ArgumentError => e
    load_settings
    flash.now[:alert] = e.message
    render :show, status: :unprocessable_entity
  end
end
