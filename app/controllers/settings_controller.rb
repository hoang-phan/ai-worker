class SettingsController < ApplicationController
  def show
    load_settings
  end

  def update
    notice = apply_settings
    redirect_to settings_path, notice: notice
  rescue ArgumentError => e
    load_settings
    flash.now[:alert] = e.message
    render :show, status: :unprocessable_entity
  end

  private

  def apply_settings
    if params[:rotation]
      AiCli::Rotation.weights = params[:rotation].to_unsafe_h
      AiCli::Rotation.enabled? ? "Round robin saved." : "Round robin turned off."
    else
      AiCli::Runner.agent = params[:agent]
      "Agent set to #{AiCli::Runner.agent}."
    end
  end

  def load_settings
    @agent = AiCli::Runner.agent
    @rotation = AiCli::Rotation.weights
  end
end
