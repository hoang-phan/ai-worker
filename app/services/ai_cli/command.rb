require "json"
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

    DEFAULT_EXECUTABLE_CHECK = Cursor::DEFAULT_EXECUTABLE_CHECK
    DEFAULT_HELP_PROBE = Cursor::DEFAULT_HELP_PROBE

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
      builder_for_agent.to_a
    end

    # MCP servers from a claude-format `{"mcpServers": {...}}` file.
    def self.mcp_servers(mcp_config)
      JSON.parse(File.read(mcp_config)).fetch("mcpServers", {})
    end

    private

    attr_reader :agent, :prompt, :allowed_tools, :mcp_config, :disallowed_tools, :model, :effort, :verbose,
                :executable_check, :help_probe

    def builder_for_agent
      case agent
      when "claude"
        Claude.new(prompt: prompt, allowed_tools: allowed_tools, mcp_config: mcp_config,
                   disallowed_tools: disallowed_tools, model: model, effort: effort, verbose: verbose)
      when "codex"
        Codex.new(prompt: prompt, mcp_config: mcp_config, model: model, effort: effort)
      when "cursor"
        Cursor.new(prompt: prompt, mcp_config: mcp_config, executable_check: executable_check, help_probe: help_probe)
      else
        raise CommandError, "unknown AGENT #{agent.inspect} (expected one of #{AGENTS.keys.join(", ")})"
      end
    end
  end
end
