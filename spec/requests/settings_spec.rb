require "rails_helper"

RSpec.describe "Settings", type: :request do
  before { AiCli::AgentSetting.current = "claude" }

  describe "GET show" do
    it "shows the settings page" do
      get settings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Settings")
    end
  end

  describe "PATCH update" do
    it "sets a valid agent and redirects with a notice" do
      new_agent = (AiCli::AgentSetting.available - [ "claude" ]).first

      patch settings_path, params: { agent: new_agent }

      expect(response).to redirect_to(settings_path)
      expect(flash[:notice]).to eq("Agent set to #{new_agent}.")
      expect(AiCli::AgentSetting.current(env: {})).to eq(new_agent)
    end

    it "rejects an unknown agent with 422 and shows the alert" do
      patch settings_path, params: { agent: "nope" }

      expect(response).to have_http_status(422)
      expect(flash[:alert]).to include("unknown agent \"nope\"")
      expect(AiCli::AgentSetting.current(env: {})).to eq("claude")
    end
  end
end
