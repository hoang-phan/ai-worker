require "rails_helper"

RSpec.describe AiCli::Runner do
  let_tmpdir(:tmp, "runner")

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
    let(:log_path) { File.join(tmp, "logs", "nested", "run.log") }
    let(:spawned) { [] }
    let(:spawn) { ->(*args, **opts) { spawned << [ args, opts ]; 4242 } }
    let(:base) { %w[claude -p go] }
    let(:command) { instance_double(AiCli::Command, to_a: base) }
    let(:builder) { class_double(AiCli::Command, new: command) }
    let(:provider) { instance_double(AiCli::Provider, wrap: %w[wrapped]) }
    let(:providers) { class_double(AiCli::Providers, fetch: provider) }
    let(:runner) { described_class.new(spawn: spawn, command_builder: builder, providers: providers) }

    def spawn_env = spawned.last.first.first
    def spawn_argv = spawned.last.first.drop(1)
    def spawn_opts = spawned.last.last

    before { allow(AiCli::AgentSetting).to receive(:current).and_return("claude") }

    it "spawns the wrapped command in the project directory with stdin closed and appended logs, returning the pid" do
      pid = runner.start(tmp, "go", log_path: log_path)

      expect(pid).to eq(4242)
      expect(spawn_argv).to eq(%w[wrapped])
      expect(spawn_opts).to eq(chdir: tmp, in: File::NULL, out: [ log_path, "a" ], err: [ log_path, "a" ])
    end

    it "creates the log directory" do
      runner.start(tmp, "go", log_path: log_path)

      expect(File.directory?(File.dirname(log_path))).to be(true)
    end

    it "forwards every command option to the builder" do
      runner.start(tmp, "go", log_path: log_path, allowed_tools: "Read", mcp_config: "m.json",
                              disallowed_tools: [ "Bash" ], model: "opus", effort: "high")

      expect(builder).to have_received(:new).with(
        agent: "claude", prompt: "go", allowed_tools: "Read", mcp_config: "m.json",
        disallowed_tools: [ "Bash" ], model: "opus", effort: "high"
      )
    end

    it "passes the built argv, project directory and mcp_config to the provider's wrap" do
      runner.start(tmp, "go", log_path: log_path, mcp_config: "/mcp.json")

      expect(providers).to have_received(:fetch).with("claude")
      expect(provider).to have_received(:wrap).with(base, project_directory: tmp, mcp_config: "/mcp.json")
    end

    it "uses an explicit provider instead of the app-wide agent" do
      runner.start(tmp, "go", log_path: log_path, provider: "cursor")

      expect(builder).to have_received(:new).with(hash_including(agent: "cursor"))
      expect(providers).to have_received(:fetch).with("cursor")
    end

    it "falls back to the app-wide agent when the provider is blank" do
      allow(AiCli::AgentSetting).to receive(:current).and_return("codex")

      runner.start(tmp, "go", log_path: log_path, provider: "")

      expect(builder).to have_received(:new).with(hash_including(agent: "codex"))
      expect(providers).to have_received(:fetch).with("codex")
    end

    it "unsets this app's Bundler/Ruby variables so the project's own bundle is used" do
      runner.start(tmp, "go", log_path: log_path)

      expect(spawn_env.slice(*described_class::LEAKED_ENV).values).to all(be_nil)
      expect(spawn_env.keys).to include(*described_class::LEAKED_ENV)
      expect(spawn_env["CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS"]).to eq("0")
    end

    it "stringifies the caller's env and lets it win over the scrub" do
      runner.start(tmp, "go", log_path: log_path, env: { "RAILS_ENV" => "test", "UAT_USER" => 1 })

      expect(spawn_env).to include("RAILS_ENV" => "test", "UAT_USER" => "1")
    end

    context "with the real defaults" do
      let(:real) { described_class.new(spawn: spawn) }

      it "builds the codex argv for the app-wide agent" do
        allow(AiCli::AgentSetting).to receive(:current).and_return("codex")

        real.start(tmp, "go", log_path: log_path)

        expect(spawn_argv.first(2)).to eq(%w[codex exec])
      end

      it "wraps cursor runs with an mcp_config in the MCP file trap" do
        mcp = File.join(tmp, "mcp.json")
        File.write(mcp, { mcpServers: {} }.to_json)

        real.start(tmp, "go", log_path: log_path, provider: "cursor", mcp_config: mcp)

        expect(spawn_argv.first(2)).to eq(%w[sh -c])
        expect(File).to exist(File.join(tmp, ".cursor", "mcp.json"))
      end

      it "leaves cursor runs without an mcp_config unwrapped" do
        real.start(tmp, "go", log_path: log_path, provider: "cursor")

        expect(spawn_argv.first).not_to eq("sh")
        expect(File).not_to exist(File.join(tmp, ".cursor"))
      end

      it "rejects an unknown provider without spawning" do
        expect { real.start(tmp, "go", log_path: log_path, provider: "gemini") }
          .to raise_error(AiCli::CommandError, /unknown AGENT "gemini"/)
        expect(spawned).to be_empty
      end
    end
  end
end
