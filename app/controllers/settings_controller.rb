class SettingsController < ApplicationController
  def show
    @agent = AiCli::Runner.agent
  end

  def update
    AiCli::Runner.agent = params[:agent]
    redirect_to settings_path, notice: "Agent set to #{AiCli::Runner.agent}."
  rescue ArgumentError => e
    @agent = AiCli::Runner.agent
    flash.now[:alert] = e.message
    render :show, status: :unprocessable_entity
  end
end
