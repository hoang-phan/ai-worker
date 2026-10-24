# Shared by SettingsController and Settings::RotationsController, which both render settings/show.
# Provides #load_settings and #render_settings_error (re-renders settings/show with the error as a 422).
module SettingsScreen
  extend ActiveSupport::Concern

  private

  def load_settings
    @agent = AiCli::AgentSetting.current
    @rotation = AiCli::Rotation.weights
  end

  def render_settings_error(error)
    load_settings
    flash.now[:alert] = error.message
    render "settings/show", status: :unprocessable_entity
  end
end
