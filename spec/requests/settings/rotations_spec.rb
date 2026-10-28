require "rails_helper"

RSpec.describe "Settings rotation", type: :request do
  describe "PATCH update" do
    it "saves the weights" do
      patch settings_rotation_path, params: { rotation: { claude: "5", codex: "3" } }

      expect(response).to redirect_to(settings_path)
      expect(flash[:notice]).to eq("Round robin saved.")
      expect(AiCli::Rotation.weights).to include("claude" => 5, "codex" => 3)
    end

    it "says round robin is turned off when every weight is zero" do
      patch settings_rotation_path, params: { rotation: { claude: "0", codex: "0" } }

      expect(response).to redirect_to(settings_path)
      expect(flash[:notice]).to eq("Round robin turned off.")
      expect(AiCli::Rotation).not_to be_enabled
    end

    it "rejects bad weights with 422" do
      patch settings_rotation_path, params: { rotation: { nope: "1" } }

      expect(response).to have_http_status(422)
      expect(flash[:alert]).to include("unknown agent")
    end
  end
end
