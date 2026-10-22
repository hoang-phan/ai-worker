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

  describe ".start" do
    it "forwards every argument to #start" do
      runner = instance_double(described_class)
      allow(described_class).to receive(:new).and_return(runner)
      expect(runner).to receive(:start).with(
        tmp, "go", log_path: "x.log", allowed_tools: "Read", mcp_config: "m.json", env: { "A" => "b" },
        disallowed_tools: [ "Bash" ], model: "opus", effort: "high"
      ).and_return(7)

      pid = described_class.start(tmp, "go", log_path: "x.log", allowed_tools: "Read", mcp_config: "m.json",
                                  env: { "A" => "b" }, disallowed_tools: [ "Bash" ], model: "opus", effort: "high")
      expect(pid).to eq(7)
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

  describe "#spawn_env" do
    subject(:env) { described_class.new.send(:spawn_env, caller_env) }

    let(:caller_env) { {} }

    it "maps every leaked variable to nil and sets the BG wait ceiling" do
      expect(env.slice(*described_class::LEAKED_ENV).values).to all(be_nil)
      expect(env.keys).to include(*described_class::LEAKED_ENV)
      expect(env["CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS"]).to eq("0")
    end

    context "with caller values" do
      let(:caller_env) { { "RAILS_ENV" => "test", "UAT_USER" => 1 } }

      it "stringifies them and lets them override the scrub" do
        expect(env).to include("RAILS_ENV" => "test", "UAT_USER" => "1")
      end
    end
  end

  describe "#agent_command" do
    let(:base) { %w[claude -p go] }
    let(:file) { instance_double(AiCli::CursorMcpFile) }
    let(:command) { instance_double(AiCli::Command, to_a: base) }

    before do
      allow(described_class).to receive(:agent).and_return(agent)
      allow(AiCli::Command).to receive(:new).and_return(command)
      allow(AiCli::CursorMcpFile).to receive(:new).with(tmp, "/mcp.json").and_return(file)
      allow(file).to receive(:wrap).with(base).and_return(%w[wrapped])
    end

    def build(mcp_config)
      described_class.new.send(:agent_command, tmp, "go", mcp_config: mcp_config)
    end

    context "when the agent is cursor" do
      let(:agent) { "cursor" }

      it "wraps the command when an mcp_config is given" do
        expect(build("/mcp.json")).to eq(%w[wrapped])
      end

      it "leaves the command alone without an mcp_config" do
        expect(build(nil)).to eq(base)
      end
    end

    context "when the agent is not cursor" do
      let(:agent) { "claude" }

      it "does not wrap even with an mcp_config" do
        expect(build("/mcp.json")).to eq(base)
      end
    end
  end
end
