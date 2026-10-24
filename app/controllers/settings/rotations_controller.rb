class Settings::RotationsController < ApplicationController
  include SettingsScreen

  def update
    AiCli::Rotation.weights = params.require(:rotation).to_unsafe_h
    notice = AiCli::Rotation.enabled? ? "Round robin saved." : "Round robin turned off."
    redirect_to settings_path, notice: notice
  rescue ArgumentError => e
    render_settings_error(e)
  end
end
