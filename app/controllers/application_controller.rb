class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  # Shared by the settings screens, which re-render settings/show on error.
  def load_settings
    @agent = AiCli::AgentSetting.current
    @rotation = AiCli::Rotation.weights
  end
end
