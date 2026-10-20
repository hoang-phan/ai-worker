require "json"
require "open3"

module AiCli
  # Builds the argv for one non-interactive agent run (see Runner for how it is
  # spawned). Pure apart from two lookups, both injectable so specs never shell
  # out: executable_check (is this binary on PATH?) and help_probe (output of
  # `<binary> --help`, used to detect cursor's --approve-mcps).
  class Command
    # Non-interactive invocation per agent. stdin is /dev/null, so every
    # agent must be told to skip permission prompts or it would hang.
    # To support another CLI, add an entry here.
    AGENTS = {
      "claude" => { binary: "claude", args: [ "-p", :prompt, "--dangerously-skip-permissions" ] },
      "cursor" => { binary: "agent", args: [ "-p", :prompt, "--force" ] },
      "codex" => { binary: "codex", args: [ "exec", "--dangerously-bypass-approvals-and-sandbox", :prompt ] }
    }.freeze

    DEFAULT_EXECUTABLE_CHECK = lambda do |name|
      ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? do |dir|
        path = File.join(dir, name)
        File.executable?(path) && !File.directory?(path)
      end
    end

    DEFAULT_HELP_PROBE = lambda do |binary|
      out, _status = Open3.capture2e(binary, "--help")
      out
    rescue SystemCallError
      ""
    end

    # verbose: AI_VERBOSE=1 switches the claude log from a single end-of-run blob to incremental stream-json events,
    # set before boot, e.g. `AI_VERBOSE=1 bin/dev`. Only applies to claude.
    def initialize(agent:, prompt:, allowed_tools: nil, mcp_config: nil, disallowed_tools: [], model: nil, effort: nil,
                   verbose: ENV["AI_VERBOSE"].present?, executable_check: DEFAULT_EXECUTABLE_CHECK, help_probe: DEFAULT_HELP_PROBE)
      @agent = agent
      @prompt = prompt
      @allowed_tools = allowed_tools
      @mcp_config = mcp_config
      @disallowed_tools = disallowed_tools
      @model = model
      @effort = effort
      @verbose = verbose
      @executable_check = executable_check
      @help_probe = help_probe
    end

    def to_a
      spec = AGENTS[agent] or raise CommandError, "unknown AGENT #{agent.inspect} (expected one of #{AGENTS.keys.join(", ")})"
      args = spec[:args].map { |arg| arg == :prompt ? prompt : arg }
      if agent == "claude" && allowed_tools.present?
        args = args.map { |arg| arg == "--dangerously-skip-permissions" ? [ "--allowedTools", *allowed_tools ] : arg }.flatten
      end
      binary = binary_for(spec)
      command = [ binary, *args ]
      command += [ "--mcp-config", mcp_config.to_s ] if agent == "claude" && mcp_config.present?
      command.insert(2, *codex_mcp_overrides) if agent == "codex" && mcp_config.present? # before the prompt
      command << "--approve-mcps" if agent == "cursor" && mcp_config.present? && cursor_supports?(binary, "--approve-mcps")
      command += [ "--disallowedTools", *disallowed_tools ] if agent == "claude" && disallowed_tools.present?
      command += [ "--model", model.to_s ] if agent == "claude" && model.present?
      command += [ "--effort", effort.to_s ] if agent == "claude" && effort.present?
      command += [ "--output-format", "stream-json", "--verbose", "--include-partial-messages" ] if agent == "claude" && verbose
      command
    end

    # MCP servers from a claude-format `{"mcpServers": {...}}` file.
    def self.mcp_servers(mcp_config)
      JSON.parse(File.read(mcp_config)).fetch("mcpServers", {})
    end

    private

    attr_reader :agent, :prompt, :allowed_tools, :mcp_config, :disallowed_tools, :model, :effort, :verbose,
                :executable_check, :help_probe

    # Cursor's CLI is installed as `agent` by newer versions and `cursor-agent` by older ones.
    def binary_for(spec)
      return spec[:binary] unless agent == "cursor"

      [ spec[:binary], "cursor-agent" ].find { |name| executable_check.call(name) } || spec[:binary]
    end

    def cursor_supports?(binary, flag)
      help_probe.call(binary).to_s.include?(flag)
    end

    # codex has no per-run MCP config file; each server is set field by field with TOML values (JSON strings and
    # arrays of strings are valid TOML).
    def codex_mcp_overrides
      self.class.mcp_servers(mcp_config).flat_map do |name, server|
        overrides = { "command" => server["command"].to_json, "startup_timeout_sec" => 90 }
        overrides["args"] = Array(server["args"]).to_json if server["args"]
        overrides["env"] = "{" + server["env"].map { |k, v| "#{k.to_json} = #{v.to_json}" }.join(", ") + "}" if server["env"].present?
        overrides.flat_map { |key, value| [ "-c", "mcp_servers.#{name}.#{key}=#{value}" ] }
      end
    end
  end
end
