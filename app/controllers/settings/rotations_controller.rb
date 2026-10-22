class Settings::RotationsController < ApplicationController
  def update
    AiCli::Rotation.weights = params.require(:rotation).to_unsafe_h
    notice = AiCli::Rotation.enabled? ? "Round robin saved." : "Round robin turned off."
    redirect_to settings_path, notice: notice
  rescue ArgumentError => e
    load_settings
    flash.now[:alert] = e.message
    render "settings/show", status: :unprocessable_entity
  end
end
