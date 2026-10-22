require "rails_helper"

RSpec.describe "Settings", type: :request do
  # The test env uses a null cache store, so stand in for the persisted agent.
  let(:agent) { { value: "claude" } }

  before do
    allow(AiCli::AgentSetting).to receive(:current) { agent[:value] }
    allow(AiCli::AgentSetting).to receive(:current=).and_wrap_original do |original, name|
      original.call(name) # validates the name; the null store drops the write
      agent[:value] = name.to_s
    end
  end

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
    end

    it "rejects an unknown agent with 422 and shows the alert" do
      patch settings_path, params: { agent: "nope" }

      expect(response).to have_http_status(422)
      expect(flash[:alert]).to include("unknown agent \"nope\"")
      expect(agent[:value]).to eq("claude")
    end
  end
end
