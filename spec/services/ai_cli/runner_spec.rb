require "rails_helper"

RSpec.describe AiCli::Runner do
  let(:tmp) { Dir.mktmpdir("runner") }

  after { FileUtils.remove_entry(tmp) }

  describe "agent setting delegation" do
    it "delegates to AiCli::AgentSetting" do
      allow(AiCli::AgentSetting).to receive(:current).and_return("codex")
      allow(AiCli::AgentSetting).to receive(:available).and_return(%w[codex])
      expect(AiCli::AgentSetting).to receive(:current=).with("codex")

      expect(described_class.agent).to eq("codex")
      expect(described_class.available_agents).to eq(%w[codex])
      described_class.agent = "codex"
    end
  end

  describe "#start" do
    def spawned_env
      captured = nil
      allow(Process).to receive(:spawn) { |env, *_rest, **_opts| captured = env; 4242 }
      yield
      captured
    end

    it "unsets this app's Bundler/Ruby variables so the project's own bundle is used" do
      env = spawned_env { described_class.start(tmp, "go", log_path: File.join(tmp, "run.log")) }

      %w[BUNDLE_GEMFILE BUNDLER_VERSION BUNDLE_BIN_PATH RUBYOPT RUBYLIB RAILS_ENV].each do |name|
        expect(env).to include(name => nil)
      end
      expect(env["CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS"]).to eq("0")
    end

    it "lets the caller's env win over the scrub" do
      env = spawned_env do
        described_class.start(tmp, "go", log_path: File.join(tmp, "run.log"), env: { "RAILS_ENV" => "test", "UAT_USER" => 1 })
      end

      expect(env).to include("RAILS_ENV" => "test", "UAT_USER" => "1")
    end
  end
end
